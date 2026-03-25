#!/usr/bin/env node
/**
 * dataset_stats.mjs — Quick statistics for the dataset.
 *
 * Usage:
 *   node dataset_stats.mjs                  # summary per channel
 *   node dataset_stats.mjs --videos         # detailed per-video breakdown
 *   node dataset_stats.mjs --channel NAME   # stats for one channel only
 *   node dataset_stats.mjs --json           # JSON output
 *   node dataset_stats.mjs --source DIR     # source dir for total count (mp3s)
 *   node dataset_stats.mjs --total N        # override total video count manually
 */

import { readdir, stat } from "node:fs/promises";
import { join, relative } from "node:path";
import { existsSync, readdirSync, statSync } from "node:fs";
import { execSync } from "node:child_process";

const DATA_DIR = new URL("./data/", import.meta.url).pathname;
const DEFAULT_SOURCE = "/Volumes/DOMOVINA1TB/fetch_domovina_tv_output";

// --- Args ---
const args = process.argv.slice(2);
const showVideos = args.includes("--videos");
const jsonOutput = args.includes("--json");
const channelFilter = args.includes("--channel")
  ? args[args.indexOf("--channel") + 1]
  : null;
const sourceDir = args.includes("--source")
  ? args[args.indexOf("--source") + 1]
  : DEFAULT_SOURCE;
const manualTotal = args.includes("--total")
  ? parseInt(args[args.indexOf("--total") + 1], 10)
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
    // Whisper prompt uses _ not . as separator
    "_whisper_prompt.txt",
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

function git(cmd) {
  return execSync(cmd, { encoding: "utf8", cwd: DATA_DIR }).trim();
}

function getGitStats() {
  try {
    const commitCount = parseInt(git("git rev-list --count HEAD"), 10);
    const firstCommit = git("git rev-list --max-parents=0 HEAD");
    const firstDate = git(`git log --format=%ai ${firstCommit}`).slice(0, 10);
    const lastDate = git("git log -1 --format=%ai").slice(0, 10);

    // count-objects -v gives sizes in KiB
    const countObj = git("git count-objects -v");
    const sizeKiB = parseInt(countObj.match(/^size:\s*(\d+)/m)?.[1] || "0", 10);
    const sizePackKiB = parseInt(countObj.match(/^size-pack:\s*(\d+)/m)?.[1] || "0", 10);
    const totalBytes = (sizeKiB + sizePackKiB) * 1024;

    return { commitCount, firstDate, lastDate, totalBytes };
  } catch {
    return null;
  }
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

  const gitStats = getGitStats();

  const result = {
    channels: [],
    totals: { channels: 0, videos: 0, files: 0, bytes: 0, extCounts: {}, videosWithOutline: 0, videosWithArticle: 0 },
    git: gitStats,
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

    // Count unique videos with outline/article
    for (const [, data] of videoMap) {
      if (data.extCounts[".outline.json"]) result.totals.videosWithOutline++;
      if (data.extCounts[".article.json"]) result.totals.videosWithArticle++;
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

  // Git statistics
  if (gitStats) {
    console.log(`  Git repository:`);
    console.log(`    Commitova:    ${gitStats.commitCount.toLocaleString()}`);
    console.log(`    Raspon:       ${gitStats.firstDate} — ${gitStats.lastDate}`);
    console.log(`    Repo velicina: ${formatBytes(gitStats.totalBytes)}`);
    console.log();
  }

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

  // --- Pipeline progress ---
  const ec = result.totals.extCounts;

  // Resolve total: --total flag > source dir mp3 count > .info.json in dataset
  let total = ec[".info.json"] || result.totals.videos;
  let totalSource = "dataset .info.json";
  if (manualTotal) {
    total = manualTotal;
    totalSource = "--total flag";
  } else {
    // Try to count mp3s from source dir
    const srcDir = sourceDir;
    if (existsSync(srcDir)) {
      let mp3Count = 0;
      try {
        const dirs = readdirSync(srcDir).filter(f => {
          try { return statSync(join(srcDir, f)).isDirectory() && !f.startsWith('.'); }
          catch { return false; }
        });
        for (const d of dirs) {
          try {
            const files = readdirSync(join(srcDir, d));
            for (const f of files) {
              if (!f.startsWith('._') && f.endsWith('.mp3')) mp3Count++;
            }
          } catch {}
        }
      } catch {}
      if (mp3Count > 0) {
        total = mp3Count;
        totalSource = `${srcDir} (.mp3)`;
      }
    }
  }

  if (total > 0) {
    // For outline/article, count unique videos (multiple model versions exist)
    const outlineVideos = result.totals.videosWithOutline || 0;
    const articleVideos = result.totals.videosWithArticle || 0;

    const pipeline = [
      { section: "Download & konverzija" },
      { label: "Metadata (.info.json)",            count: ec[".info.json"] || 0,           base: total },
      { label: "Opisi (.description)",             count: ec[".description"] || 0,         base: total },
      { section: "Whisper (OpenAI)" },
      { label: "Whisper prompt (.txt)",            count: ec["_whisper_prompt.txt"] || 0,  base: total },
      { label: "Whisper transkripcija (.srt)",     count: ec[".srt"] || 0,                 base: total },
      { label: "Whisper diarizacija",              count: ec[".diarized.srt"] || 0,        base: total },
      { section: "Canary (NVIDIA)" },
      { label: "Canary transkripcija",             count: ec[".canary.srt"] || 0,          base: total },
      { label: "Canary CSV",                       count: ec[".canary.csv"] || 0,          base: total },
      { label: "Canary diarizacija",               count: ec[".canary.diarized.srt"] || 0, base: total },
      { section: "Gemini (Google)" },
      { label: "Gemini sazeci",                    count: ec[".canary.summary.json"] || 0, blocked: ec[".canary.summary.blocked.json"] || 0, base: total },
      { label: "Gemini outlinei",                  count: outlineVideos, extra: ec[".outline.json"] || 0, base: total },
      { label: "Gemini clanci",                    count: articleVideos, extra: ec[".article.json"] || 0, blocked: ec[".canary.diarized.blocked.json"] || 0, base: total },
      { section: "RAG priprema" },
      { label: "RAG chunks",                       count: ec[".rag_chunks.jsonl"] || 0,    base: total },
      { label: "RAG import",                       count: ec[".rag_import.jsonl"] || 0,    base: total },
      { label: "RAG combined",                     count: ec[".rag_combined.jsonl"] || 0,  base: total },
    ];

    const BAR_WIDTH = 20;
    console.log(`\n  Pipeline progress (${total} videa, izvor: ${totalSource}):\n`);
    for (const s of pipeline) {
      if (s.section) {
        console.log(`\n    -- ${s.section} --`);
        continue;
      }
      const ratio = Math.min(s.count / s.base, 1);
      const pct = (ratio * 100).toFixed(3);
      const filled = Math.round(ratio * BAR_WIDTH);
      const bar = "\u2588".repeat(filled) + "\u2591".repeat(BAR_WIDTH - filled);
      const blocked = s.blocked ? ` (+${s.blocked} blocked)` : "";
      const extra = s.extra ? ` (${s.extra} files)` : "";
      console.log(
        `    ${pad(s.label, 30)} ${bar} ${rpad(pct + "%", 9)} ${rpad(s.count, 5)}/${s.base}${blocked}${extra}`
      );
    }
  }
  console.log();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
