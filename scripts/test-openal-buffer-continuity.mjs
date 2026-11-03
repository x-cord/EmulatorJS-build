// Run: node scripts/test-openal-buffer-continuity.mjs /path/to/playwright/index.mjs
import assert from 'node:assert/strict';
const { chromium } = await import(process.argv[2] || 'playwright');
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM || '/usr/bin/chromium',
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
try {
  const page = await browser.newPage();
  const results = await page.evaluate(async () => {
    const results = [];
    for (const [sourceRate, contextRate, ragged] of [[44100, 48000, false], [44100, 44100, true], [44100, 44100, false], [48000, 48000, false]]) {
      const signal = new Float32Array(sourceRate);
      for (let i = 0; i < signal.length; ++i)
        signal[i] = 0.5 * Math.sin(2 * Math.PI * 1800 * i / sourceRate);
      async function render(split) {
        const ctx = new OfflineAudioContext(1, contextRate, contextRate);
        // Whole buffers and a partial packet, as in RetroArch's OpenAL writer.
        const packets = sourceRate === 44100 ? [256, 256, 223] : [256, 256, 256, 32];
        for (let pos = 0, packet = 0; pos < signal.length; ++packet) {
          const count = Math.min(signal.length - pos, split ? (ragged ? packets[packet % packets.length] : 256) : signal.length);
          const data = ctx.createBuffer(1, count, sourceRate);
          data.copyToChannel(signal.subarray(pos, pos + count), 0);
          const node = ctx.createBufferSource();
          node.buffer = data;
          node.connect(ctx.destination);
          node.start(pos / sourceRate);
          pos += count;
        }
        return (await ctx.startRendering()).getChannelData(0);
      }
      const whole = await render(false), split = await render(true);
      let maxError = 0, energy = 0;
      // Exclude the outer edges shared by both renderings.
      for (let i = 256; i < contextRate - 256; ++i) {
        const difference = split[i] - whole[i];
        maxError = Math.max(maxError, Math.abs(difference));
        energy += difference * difference;
      }
      results.push({ sourceRate, contextRate, ragged, maxError, rmsError: Math.sqrt(energy / (contextRate - 512)) });
    }
    return results;
  });
  console.log(JSON.stringify(results, null, 2));
  assert(results[0].maxError > 0.01, 'The control must reproduce buffer-join spikes');
  assert(results[1].maxError > 0.01, 'The control must reproduce partial-packet phase errors');
  for (const result of results.slice(2))
    assert(result.maxError < 1e-6, 'Matching the context clock must preserve continuity');
} finally {
  await browser.close();
}
