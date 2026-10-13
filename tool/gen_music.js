// Synthesises two looping background-music tracks into assets/audio as
// 16-bit mono WAV, in the same pure-Node/no-samples style as gen_audio.js
// (see that file for the SFX). Run from the project root: node tool/gen_music.js
//
// Both tracks are an 8-bar classical-pastiche loop in C major: a plucked
// "harpsichord" melody over an Alberti-style broken-chord accompaniment and
// a quarter-note bass, the harmonic cliche I-V-vi-IV (menu) / I-IV-V-vi
// (game) that genre fans will recognise as "cheerful classical". The game
// track is the same idiom sped up with finer subdivisions and a soft
// rhythmic tick, so it reads as "the same game, more energy" rather than a
// jarring style switch between menu and play.
const fs = require('fs');
const path = require('path');

const RATE = 22050;
const OUT = path.join(__dirname, '..', 'assets', 'audio');
fs.mkdirSync(OUT, { recursive: true });

let seed = 54321;
const noise = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x3fffffff - 1;
};

function write(name, samples, peak = 0.7) {
  let max = 0;
  for (const s of samples) max = Math.max(max, Math.abs(s));
  const gain = max > 0 ? peak / max : 1;
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((s, i) => data.writeInt16LE(Math.round(s * gain * 32767), i * 2));
  const head = Buffer.alloc(44);
  head.write('RIFF', 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write('WAVEfmt ', 8);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20);
  head.writeUInt16LE(1, 22);
  head.writeUInt32LE(RATE, 24);
  head.writeUInt32LE(RATE * 2, 28);
  head.writeUInt16LE(2, 32);
  head.writeUInt16LE(16, 34);
  head.write('data', 36);
  head.writeUInt32LE(data.length, 40);
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([head, data]));
  console.log(name, (samples.length / RATE).toFixed(2) + 's');
}

const buf = (seconds) => new Float64Array(Math.round(seconds * RATE));
const midiFreq = (n) => 440 * Math.pow(2, (n - 69) / 12);
const lowpass = (x, cutoff) => {
  const a = 1 - Math.exp((-2 * Math.PI * cutoff) / RATE);
  let y = 0;
  for (let i = 0; i < x.length; i++) {
    y += a * (x[i] - y);
    x[i] = y;
  }
  return x;
};

// Mixes `synth(t)` for `durSec` seconds into `target`, starting at `startSec`.
function addNote(target, startSec, durSec, synth) {
  const from = Math.round(startSec * RATE);
  const count = Math.round(durSec * RATE);
  for (let i = 0; i < count && from + i >= 0 && from + i < target.length; i++) {
    target[from + i] += synth(i / RATE);
  }
}

// Plucked, bright, fixed-rate decay (like a harpsichord string: it rings at
// its own pace regardless of the written note length, the way a real pluck
// does) — used for the melody.
function pluck(f, gain = 1) {
  return (t) => {
    const env = Math.min(1, t * 500) * Math.exp(-t * 6.5);
    return env * gain * (Math.sin(2 * Math.PI * f * t) + 0.35 * Math.sin(4 * Math.PI * f * t) + 0.12 * Math.sin(6 * Math.PI * f * t));
  };
}

// Softer / quieter sibling, longer ring — the Alberti-bass accompaniment
// figure sits underneath the melody, so it must not compete with it.
function arpeggio(f, gain = 0.5) {
  return (t) => {
    const env = Math.min(1, t * 500) * Math.exp(-t * 5);
    return env * gain * (Math.sin(2 * Math.PI * f * t) + 0.2 * Math.sin(4 * Math.PI * f * t));
  };
}

// Rounder and slower-decaying — the quarter-note bass.
function bass(f, gain = 0.8) {
  return (t) => {
    const env = Math.min(1, t * 300) * Math.exp(-t * 3.2);
    return env * gain * (Math.sin(2 * Math.PI * f * t) + 0.18 * Math.sin(4 * Math.PI * f * t));
  };
}

// A very soft filtered-noise tick, just enough rhythmic pulse to make the
// game track feel more driven than the menu track without turning into a
// drum kit (which would clash with the harpsichord-pastiche idiom).
function tick(target, startSec, gain = 0.18) {
  const from = Math.round(startSec * RATE);
  const n = Math.round(0.05 * RATE);
  const grain = lowpass(Float64Array.from({ length: n }, noise), 3200);
  for (let i = 0; i < n && from + i < target.length; i++) {
    const t = i / n;
    target[from + i] += grain[i] * Math.exp(-t * 30) * gain;
  }
}

// chord: [root, third, fifth] MIDI numbers. `subdivisions` 8 = eighth notes,
// 16 = sixteenth notes, one bar (4 beats) long. Pattern is the classic
// Alberti figure root-fifth-third-fifth, repeated to fill the bar.
function albertiBar(target, barStartSec, secPerBeat, chord, subdivisions, gain) {
  const [root, third, fifth] = chord;
  const pattern = [root, fifth, third, fifth];
  const step = (4 * secPerBeat) / subdivisions;
  for (let i = 0; i < subdivisions; i++) {
    const note = pattern[i % 4];
    addNote(target, barStartSec + i * step, step * 1.6, arpeggio(midiFreq(note), gain));
  }
}

function bassBar(target, barStartSec, secPerBeat, notes) {
  // notes: [[beatOffset, midi], ...] within the bar.
  for (const [beat, midi] of notes) {
    addNote(target, barStartSec + beat * secPerBeat, secPerBeat * 1.8, bass(midiFreq(midi)));
  }
}

function melodyBar(target, barStartSec, secPerBeat, notes, gain = 1) {
  // notes: [[beatOffset, midi, beatDuration], ...] within the bar.
  for (const [beat, midi, dur] of notes) {
    addNote(target, barStartSec + beat * secPerBeat, dur * secPerBeat * 1.3, pluck(midiFreq(midi), gain));
  }
}

// Chord table (MIDI root/third/fifth), C major diatonic triads.
const CHORDS = {
  C: [60, 64, 67],
  F: [53, 57, 60],
  G: [55, 59, 62],
  Am: [57, 60, 64],
};
// Bass roots one octave below the chord's own root.
const BASS_ROOT = { C: 48, F: 41, G: 43, Am: 45 };
const BASS_FIFTH = { C: 43, F: 48, G: 50, Am: 52 };

function composeMenu() {
  const bpm = 116;
  const secPerBeat = 60 / bpm;
  const bars = 8;
  const total = bars * 4 * secPerBeat;
  const x = buf(total + 0.6); // trailing tail for the last note's ring
  const progression = ['C', 'G', 'Am', 'F', 'C', 'F', 'G', 'C'];
  const melody = [
    [[0, 76, 1], [1, 79, 1], [2, 84, 1], [3, 79, 1]], // bar1 C
    [[0, 79, 1], [1, 83, 1], [2, 86, 1], [3, 83, 1]], // bar2 G
    [[0, 76, 1], [1, 81, 1], [2, 84, 1], [3, 81, 1]], // bar3 Am
    [[0, 77, 1], [1, 81, 1], [2, 84, 1], [3, 81, 1]], // bar4 F
    [[0, 76, 1], [1, 79, 1], [2, 84, 1], [3, 79, 1]], // bar5 C (= bar1)
    [[0, 81, 1], [1, 77, 1], [2, 72, 1], [3, 77, 1]], // bar6 F
    [[0, 86, 1], [1, 84, 1], [2, 83, 1], [3, 81, 1]], // bar7 G (descending run)
    [[0, 79, 1], [1, 76, 1], [2, 72, 2]], // bar8 C, lands on tonic for the loop
  ];
  for (let bar = 0; bar < bars; bar++) {
    const chordName = progression[bar];
    const barStart = bar * 4 * secPerBeat;
    albertiBar(x, barStart, secPerBeat, CHORDS[chordName], 8, 0.42);
    bassBar(x, barStart, secPerBeat, [[0, BASS_ROOT[chordName]], [2, BASS_ROOT[chordName]]]);
    melodyBar(x, barStart, secPerBeat, melody[bar], 0.9);
  }
  write('bgm_menu.wav', x, 0.78);
}

function composeGame() {
  const bpm = 150;
  const secPerBeat = 60 / bpm;
  const bars = 8;
  const total = bars * 4 * secPerBeat;
  const x = buf(total + 0.5);
  const progression = ['C', 'F', 'G', 'C', 'Am', 'F', 'G', 'C'];
  const melody = [
    [[0, 79, 0.5], [0.5, 84, 0.5], [1, 79, 0.5], [1.5, 84, 0.5], [2, 81, 1], [3, 79, 1]], // C
    [[0, 77, 0.5], [0.5, 81, 0.5], [1, 77, 0.5], [1.5, 81, 0.5], [2, 84, 1], [3, 81, 1]], // F
    [[0, 79, 0.5], [0.5, 83, 0.5], [1, 79, 0.5], [1.5, 83, 0.5], [2, 86, 1], [3, 83, 1]], // G
    [[0, 76, 0.5], [0.5, 79, 0.5], [1, 84, 0.5], [1.5, 79, 0.5], [2, 76, 1], [3, 84, 1]], // C
    [[0, 76, 0.5], [0.5, 81, 0.5], [1, 84, 0.5], [1.5, 81, 0.5], [2, 76, 1], [3, 81, 1]], // Am
    [[0, 77, 0.5], [0.5, 81, 0.5], [1, 77, 0.5], [1.5, 81, 0.5], [2, 84, 1], [3, 81, 1]], // F
    [[0, 79, 0.5], [0.5, 83, 0.5], [1, 86, 0.5], [1.5, 83, 0.5], [2, 84, 1], [3, 81, 1]], // G
    [[0, 79, 1], [1, 76, 1], [2, 72, 2]], // C, lands on tonic for the loop
  ];
  for (let bar = 0; bar < bars; bar++) {
    const chordName = progression[bar];
    const barStart = bar * 4 * secPerBeat;
    albertiBar(x, barStart, secPerBeat, CHORDS[chordName], 16, 0.38);
    bassBar(x, barStart, secPerBeat, [[0, BASS_ROOT[chordName]], [2, BASS_FIFTH[chordName]]]);
    melodyBar(x, barStart, secPerBeat, melody[bar], 1);
    for (let beat = 0; beat < 4; beat++) tick(x, barStart + beat * secPerBeat);
  }
  write('bgm_game.wav', x, 0.8);
}

composeMenu();
composeGame();
