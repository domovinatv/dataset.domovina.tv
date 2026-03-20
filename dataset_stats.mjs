#!/usr/bin/env node
/**
 * dataset_stats.mjs — Quick statistics for the dataset.
 *
 * Usage:
 *   node dataset_stats.mjs                  # summary per channel
 *   node dataset_stats.mjs --videos         # detailed per-video breakdown
 *   node dataset_stats.mjs --channel NAME   # stats for one channel only
 *   node dataset_stats.mjs --json           # JSON output
 */

import { readdir, stat } from "node:fs/promises";
import { join, relative } from "node:path";

const DATA_DIR = new URL("./data/", import.meta.url).pathname;

// --- Args ---
const args = process.argv.slice(2);
const showVideos = args.includes("--videos");
const jsonOutput = args.includes("--json");
const channelFilter = args.includes("--channel")
  ? args[args.indexOf("--channel") + 1]
  : null;

// --- Helpers ---

/** Extract video base name from a filename (same logic as sync_dataset.sh) */
function videoBase(filename) {
  return filename
    .replace(/_whisper_prompt\..+$/, "")
    .replace(/\..+$/, "");
}

/** Extract human-readable parts from video base name */
function parseVideoBase(base) {
  const dateMatch = base.match(/^(\d{8})_/);
  const date = dateMatch
    ? `${base.slice(0, 4)}-${base.slice(4, 6)}-${base.slice(6, 8)}`
    : null;

  const ytMatch = base.match(/_yt_([A-Za-z0-9_-]+)$/);
  const ytId = ytMatch ? ytMatch[1] : null;

  let title = base;
  if (dateMatch) title = title.slice(9); // remove YYYYMMDD_
  if (ytMatch) title = title.replace(/_yt_[A-Za-z0-9_-]+$/, "");
  title = title.replace(/_/g, " ");

  return { date, title, ytId };
}

/** Get file extension category */
function extCategory(filename) {
  // Order matters — check compound extensions first
  const compound = [
    // Blocked markers (must come before non-blocked variants)
    ".canary.summary.blocked.json",
    ".canary.diarized.blocked.json",
    // Canary diarized must come before plain .diarized.srt
    ".canary.diarized.srt",
    ".canary.diarized_rag_ready.json",
    ".canary.summary.json",
    ".canary.srt",
    ".canary.csv",
    ".diarized.srt",
    ".info.json",
    ".article.json",
    ".outline.json",
    ".rag_chunks.jsonl",
    ".rag_combined.jsonl",
    ".rag_import.jsonl",
    ".whisper_prompt.txt",
    ".en.vtt",
    ".hr.vtt",
  ];
  for (const ext of compound) {
    if (filename.endsWith(ext)) return ext;
  }
  // Fall back to last extension
  const m = filename.match(/(\.[^.]+)$/);
  return m ? m[1] : "(none)";
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function pad(s, n) {
  return String(s).padEnd(n);
}
function rpad(s, n) {
  return String(s).padStart(n);
}

// --- Scan ---

async function scanDir(dirPath) {
  const entries = [];
  try {
    const items = await readdir(dirPath, { withFileTypes: true });
    for (const item of items) {
      if (item.name.startsWith(".")) continue;
      const full = join(dirPath, item.name);
      if (item.isFile()) {
        const s = await stat(full);
        entries.push({ name: item.name, size: s.size, path: full });
      } else if (item.isDirectory()) {
        // Recurse into subdirs (e.g. _raw/ dirs)
        const sub = await scanDir(full);
        entries.push(...sub);
      }
    }
  } catch {
    // skip unreadable dirs
  }
  return entries;
}

async function main() {
  const channelDirs = (
    await readdir(DATA_DIR, { withFileTypes: true })
  ).filter((d) => d.isDirectory() && !d.name.startsWith("."));

  const result = {
    channels: [],
    totals: { channels: 0, videos: 0, files: 0, bytes: 0, extCounts: {} },
  };

  for (const chDir of channelDirs.sort((a, b) =>
    a.name.localeCompare(b.name)
  )) {
    if (channelFilter && chDir.name !== channelFilter) continue;

    const chPath = join(DATA_DIR, chDir.name);
    const files = await scanDir(chPath);

    // Group by video
    const videoMap = new Map();
    for (const f of files) {
      const relName = relative(chPath, f.path);
      // For files in subdirs, use the subdir name as part of grouping
      const baseName = relName.includes("/")
        ? videoBase(relName.split("/")[0])
        : videoBase(f.name);

      if (!videoMap.has(baseName)) {
        videoMap.set(baseName, { files: [], bytes: 0, extCounts: {} });
      }
      const v = videoMap.get(baseName);
      v.files.push(f);
      v.bytes += f.size;

      const ext = extCategory(f.name);
      v.extCounts[ext] = (v.extCounts[ext] || 0) + 1;
      result.totals.extCounts[ext] =
        (result.totals.extCounts[ext] || 0) + 1;
    }

    const chData = {
      name: chDir.name,
      displayName: chDir.name.replace(/_/g, " "),
      videos: videoMap.size,
      files: files.length,
      bytes: files.reduce((s, f) => s + f.size, 0),
      videoList: [],
    };

    if (showVideos || channelFilter) {
      for (const [base, data] of [...videoMap.entries()].sort()) {
        const parsed = parseVideoBase(base);
        chData.videoList.push({
          base,
          ...parsed,
          files: data.files.length,
          bytes: data.bytes,
          extCounts: data.extCounts,
        });
      }
    }

    result.channels.push(chData);
    result.totals.channels++;
    result.totals.videos += videoMap.size;
    result.totals.files += files.length;
    result.totals.bytes += chData.bytes;
  }

  // --- Output ---
  if (jsonOutput) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  // Header
  console.log(
    `\n  DATASET STATISTICS\n  ${"=".repeat(60)}\n`
  );

  // Per-channel table
  console.log(
    `  ${pad("Channel", 38)} ${rpad("Videos", 7)} ${rpad("Files", 7)} ${rpad("Size", 10)}`
  );
  console.log(`  ${"-".repeat(62)}`);

  for (const ch of result.channels) {
    console.log(
      `  ${pad(ch.displayName, 38)} ${rpad(ch.videos, 7)} ${rpad(ch.files, 7)} ${rpad(formatBytes(ch.bytes), 10)}`
    );

    if (showVideos || channelFilter) {
      for (const v of ch.videoList) {
        const label = v.date
          ? `${v.date} ${v.title.slice(0, 40)}`
          : v.base.slice(0, 50);
        const exts = Object.entries(v.extCounts)
          .map(([e, c]) => `${e}(${c})`)
          .join(" ");
        console.log(
          `    ${pad(label, 52)} ${rpad(v.files, 4)} ${rpad(formatBytes(v.bytes), 9)}  ${exts}`
        );
      }
      console.log();
    }
  }

  // Totals
  console.log(`  ${"-".repeat(62)}`);
  console.log(
    `  ${pad("TOTAL", 38)} ${rpad(result.totals.videos, 7)} ${rpad(result.totals.files, 7)} ${rpad(formatBytes(result.totals.bytes), 10)}`
  );

  // Extension breakdown
  console.log(`\n  Files by extension:`);
  const sortedExts = Object.entries(result.totals.extCounts).sort(
    (a, b) => b[1] - a[1]
  );
  for (const [ext, count] of sortedExts) {
    console.log(`    ${rpad(count, 6)}  ${ext}`);
  }
  console.log();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
