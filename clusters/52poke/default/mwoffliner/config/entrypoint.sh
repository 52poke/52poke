#!/usr/bin/env bash
set -euo pipefail

run_mwoffliner() {
  mwoffliner "$@"
}

find_zim_asset() {
  local asset_dir="${RELEASE_ASSET_DIR:-/out}"
  local asset_path

  asset_path="$(ls -t "${asset_dir}"/*.zim 2>/dev/null | head -n 1 || true)"
  if [[ -z "${asset_path}" ]]; then
    echo "No ZIM file found in ${asset_dir}" >&2
    exit 1
  fi

  printf '%s\n' "${asset_path}"
}

upload_release_asset() {
  node <<'NODE'
const fs = require("node:fs");
const https = require("node:https");
const crypto = require("node:crypto");
const { URL } = require("node:url");

const repo = process.env.GITHUB_REPOSITORY;
const token = process.env.GITHUB_TOKEN;
const tag = process.env.RELEASE_TAG;
const assetPath = process.env.RELEASE_ASSET_PATH;
const zipPassword = process.env.RELEASE_ZIP_PASSWORD || "";
const assetName = process.env.RELEASE_ASSET_NAME || `mwoffliner-${tag}.zip`;
const zipPath = process.env.RELEASE_ZIP_PATH || `/out/${assetName}`;
const overwrite = process.env.RELEASE_OVERWRITE || "";
const encryptedUtf8Flag = 0x0801;

const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n += 1) {
  let c = n;
  for (let k = 0; k < 8; k += 1) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  crcTable[n] = c >>> 0;
}

function updateCrc(crc, byte) {
  return (crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8)) >>> 0;
}

function crc32File(path) {
  const fd = fs.openSync(path, "r");
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  let crc = 0xffffffff;

  try {
    while (true) {
      const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (bytesRead === 0) {
        break;
      }

      for (let index = 0; index < bytesRead; index += 1) {
        crc = updateCrc(crc, buffer[index]);
      }
    }
  } finally {
    fs.closeSync(fd);
  }

  return (crc ^ 0xffffffff) >>> 0;
}

function initZipCrypto(password) {
  const keys = [0x12345678, 0x23456789, 0x34567890];

  function updateKeys(byte) {
    keys[0] = updateCrc(keys[0], byte);
    keys[1] = (Math.imul((keys[1] + (keys[0] & 0xff)) >>> 0, 134775813) + 1) >>> 0;
    keys[2] = updateCrc(keys[2], keys[1] >>> 24);
  }

  function decryptByte() {
    const temp = (keys[2] | 2) >>> 0;
    return (Math.imul(temp, temp ^ 1) >>> 8) & 0xff;
  }

  for (const byte of Buffer.from(password)) {
    updateKeys(byte);
  }

  return {
    encryptByte(byte) {
      const encrypted = byte ^ decryptByte();
      updateKeys(byte);
      return encrypted;
    },
  };
}

function dosDateTime(date) {
  const year = Math.max(date.getUTCFullYear(), 1980);
  const dosTime =
    (date.getUTCHours() << 11) |
    (date.getUTCMinutes() << 5) |
    Math.floor(date.getUTCSeconds() / 2);
  const dosDate =
    ((year - 1980) << 9) |
    ((date.getUTCMonth() + 1) << 5) |
    date.getUTCDate();

  return { dosDate, dosTime };
}

function writeUInt16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value);
  return buffer;
}

function writeUInt32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value >>> 0);
  return buffer;
}

function encryptBuffer(buffer, zipCrypto) {
  const encrypted = Buffer.allocUnsafe(buffer.length);
  for (let index = 0; index < buffer.length; index += 1) {
    encrypted[index] = zipCrypto.encryptByte(buffer[index]);
  }
  return encrypted;
}

function createEncryptedStoredZip(sourcePath, targetPath, password) {
  if (!password) {
    throw new Error("RELEASE_ZIP_PASSWORD is required");
  }

  const sourceStat = fs.statSync(sourcePath);
  if (sourceStat.size > 0xffffffff - 12) {
    throw new Error("ZIM file is too large for classic encrypted ZIP output");
  }

  const sourceName = sourcePath.split("/").pop();
  const sourceNameBuffer = Buffer.from(sourceName);
  const crc = crc32File(sourcePath);
  const { dosDate, dosTime } = dosDateTime(sourceStat.mtime);
  const compressedSize = sourceStat.size + 12;
  const uncompressedSize = sourceStat.size;
  const localHeaderOffset = 0;

  const localHeader = Buffer.concat([
    writeUInt32(0x04034b50),
    writeUInt16(20),
    writeUInt16(encryptedUtf8Flag),
    writeUInt16(0),
    writeUInt16(dosTime),
    writeUInt16(dosDate),
    writeUInt32(crc),
    writeUInt32(compressedSize),
    writeUInt32(uncompressedSize),
    writeUInt16(sourceNameBuffer.length),
    writeUInt16(0),
    sourceNameBuffer,
  ]);

  const zipCrypto = initZipCrypto(password);
  const encryptionHeader = crypto.randomBytes(12);
  encryptionHeader[11] = crc >>> 24;

  const output = fs.openSync(targetPath, "w");
  let offset = 0;

  try {
    fs.writeSync(output, localHeader);
    offset += localHeader.length;
    fs.writeSync(output, encryptBuffer(encryptionHeader, zipCrypto));
    offset += 12;

    const input = fs.openSync(sourcePath, "r");
    const buffer = Buffer.allocUnsafe(1024 * 1024);

    try {
      while (true) {
        const bytesRead = fs.readSync(input, buffer, 0, buffer.length, null);
        if (bytesRead === 0) {
          break;
        }

        const chunk = buffer.subarray(0, bytesRead);
        fs.writeSync(output, encryptBuffer(chunk, zipCrypto));
        offset += bytesRead;
      }
    } finally {
      fs.closeSync(input);
    }

    const centralDirectoryOffset = offset;
    const centralDirectoryHeader = Buffer.concat([
      writeUInt32(0x02014b50),
      writeUInt16(20),
      writeUInt16(20),
      writeUInt16(encryptedUtf8Flag),
      writeUInt16(0),
      writeUInt16(dosTime),
      writeUInt16(dosDate),
      writeUInt32(crc),
      writeUInt32(compressedSize),
      writeUInt32(uncompressedSize),
      writeUInt16(sourceNameBuffer.length),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt32(0),
      writeUInt32(localHeaderOffset),
      sourceNameBuffer,
    ]);

    fs.writeSync(output, centralDirectoryHeader);
    offset += centralDirectoryHeader.length;

    const endOfCentralDirectory = Buffer.concat([
      writeUInt32(0x06054b50),
      writeUInt16(0),
      writeUInt16(0),
      writeUInt16(1),
      writeUInt16(1),
      writeUInt32(centralDirectoryHeader.length),
      writeUInt32(centralDirectoryOffset),
      writeUInt16(0),
    ]);

    fs.writeSync(output, endOfCentralDirectory);
  } finally {
    fs.closeSync(output);
  }

  return targetPath;
}

function request(method, url, { headers = {}, body, streamPath } = {}) {
  return new Promise((resolve, reject) => {
    const requestHeaders = {
      "Accept": "application/vnd.github+json",
      "Authorization": `Bearer ${token}`,
      "User-Agent": "52poke-mwoffliner",
      "X-GitHub-Api-Version": "2022-11-28",
      ...headers,
    };

    const req = https.request(url, { method, headers: requestHeaders }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        resolve({
          statusCode: res.statusCode,
          body: Buffer.concat(chunks).toString("utf8"),
        });
      });
    });

    req.on("error", reject);

    if (streamPath) {
      fs.createReadStream(streamPath).on("error", reject).pipe(req);
    } else {
      req.end(body);
    }
  });
}

async function githubJson(method, path, body, okStatuses = [200, 201]) {
  const payload = body === undefined ? undefined : JSON.stringify(body);
  const headers = {};
  if (payload !== undefined) {
    headers["Content-Type"] = "application/json";
    headers["Content-Length"] = Buffer.byteLength(payload);
  }

  const response = await request(method, `https://api.github.com${path}`, {
    headers,
    body: payload,
  });

  if (!okStatuses.includes(response.statusCode)) {
    throw new Error(`${method} ${path} failed with ${response.statusCode}: ${response.body}`);
  }

  return response.body ? JSON.parse(response.body) : null;
}

async function getOrCreateRelease() {
  const existing = await request(
    "GET",
    `https://api.github.com/repos/${repo}/releases/tags/${encodeURIComponent(tag)}`,
  );

  if (existing.statusCode === 200) {
    return JSON.parse(existing.body);
  }
  if (existing.statusCode !== 404) {
    throw new Error(`GET release ${tag} failed with ${existing.statusCode}: ${existing.body}`);
  }

  return githubJson("POST", `/repos/${repo}/releases`, {
    tag_name: tag,
    name: tag,
    prerelease: false,
  });
}

async function deleteAssetIfExists(releaseId) {
  const assets = await githubJson("GET", `/repos/${repo}/releases/${releaseId}/assets`);
  const existing = assets.find((asset) => asset.name === assetName);

  if (!existing) {
    return;
  }

  await githubJson(
    "DELETE",
    `/repos/${repo}/releases/assets/${existing.id}`,
    undefined,
    [204],
  );
}

async function uploadAsset(uploadUrl) {
  const endpoint = new URL(uploadUrl.split("{")[0]);
  endpoint.searchParams.set("name", assetName);

  const stat = fs.statSync(zipPath);
  const response = await request("POST", endpoint, {
    headers: {
      "Content-Length": stat.size,
      "Content-Type": "application/zip",
    },
    streamPath: zipPath,
  });

  if (response.statusCode !== 201) {
    throw new Error(`Upload asset failed with ${response.statusCode}: ${response.body}`);
  }
}

async function main() {
  createEncryptedStoredZip(assetPath, zipPath, zipPassword);

  const release = await getOrCreateRelease();

  if (overwrite) {
    await deleteAssetIfExists(release.id);
  }

  await uploadAsset(release.upload_url);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
}

main() {
  run_mwoffliner "$@"

  if [[ "${RELEASE_UPLOAD:-}" != "" ]]; then
    if [[ -z "${GITHUB_REPOSITORY:-}" || -z "${GITHUB_TOKEN:-}" ]]; then
      echo "RELEASE_UPLOAD set but GITHUB_REPOSITORY or GITHUB_TOKEN missing" >&2
      exit 1
    fi

    export RELEASE_TAG="${RELEASE_TAG:-$(date -u +%Y.%m.%d-zim)}"
    export RELEASE_ASSET_PATH="${RELEASE_ASSET_PATH:-$(find_zim_asset)}"

    upload_release_asset
  fi
}

main "$@"
