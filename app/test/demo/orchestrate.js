// Demo pipeline orchestrator.
//
// Stage A: decode the receiver's rendered QR PNGs with jsqr — this is the
//   "camera" of the pipeline: real pixels in, real frame strings out, fed to
//   the Dart payer harness.
// Stage B (run after both harnesses): decode the payer's confirmation PNGs,
//   assemble all frames from both devices into the demo video, and cut a
//   side-by-side and a phone-cropped edit via ffmpeg.
//
// Usage:
//   node orchestrate.js decode-request            # after receiver phase 1
//   node orchestrate.js decode-confirmation       # after payer harness
//   node orchestrate.js video                     # after receiver phase 2
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const jsQR = require('jsqr');
const { PNG } = require('pngjs');

const ROOT = '/tmp/pfdemo';
const REC = path.join(ROOT, 'receiver');
const PAY = path.join(ROOT, 'payer');

function decodeQrFrames(dir, outName) {
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.png'))
    .sort();
  const seen = new Set();
  const frames = [];
  for (const f of files) {
    const png = PNG.sync.read(fs.readFileSync(path.join(dir, f)));
    const code = jsQR(new Uint8ClampedArray(png.data), png.width, png.height);
    if (code && code.data) {
      if (!seen.has(code.data)) {
        seen.add(code.data);
        frames.push(code.data);
      }
    }
  }
  fs.writeFileSync(path.join(ROOT, outName), frames.join('\n'));
  console.log(`decoded ${frames.length} unique QR frames -> ${outName}`);
  return frames;
}

function decodePayerConfirmation() {
  // The payer's animated-QR PNGs, decoded for real — pixels → jsQR → frame
  // strings. A valid frame serializes as 'PF_FTN:1:...' (see FountainPacket);
  // scan artifacts are dropped, not silently mangled.
  decodeQrFrames(path.join(PAY, 'frames'), 'payer_conf_qr_raw.txt');
  const isFrame = (s) => s.startsWith('PF_FTN:1:');
  const frames = fs
    .readFileSync(path.join(ROOT, 'payer_conf_qr_raw.txt'), 'utf8')
    .split('\n')
    .filter(Boolean)
    .filter(isFrame);
  fs.writeFileSync(
    path.join(PAY, 'conf_frames_decoded.txt'),
    frames.join('\n')
  );
  console.log(`payer confirmation: ${frames.length} valid frames ready for receiver`);
  if (frames.length === 0) throw new Error('no valid fountain frames decoded');
}

function buildVideo() {
  const seq = [];
  const add = (dir, name, dur) => {
    const p = path.join(dir, `${name}.png`);
    if (!fs.existsSync(p)) throw new Error(`missing frame: ${p}`);
    seq.push({ p, dur });
  };
  const R1 = path.join(REC, 'p1');
  const PF = path.join(PAY, 'frames');
  const R2 = path.join(REC, 'p2');

  // Phone-frame timeline, 1080x1920 (2x renders are 786x1704, scaled).
  // Act 1 — receiver offers, payer scans (offline both sides)
  add(R1, 's1r_idle', 2.0);
  for (let i = 0; i < 20; i++) add(R1, `s1r_qr_${String(i).padStart(2, '0')}`, 0.4);
  for (let i = 0; i < 4; i++) add(PF, `s2a_scanning_${i}`, 0.7);
  add(PF, 's2b_request', 3.0);
  // Act 2 — payer pays, confirmation streams back over the optical channel
  for (let i = 0; i < 20; i++) add(PF, `s3_conf_${String(i).padStart(2, '0')}`, 0.4);
  add(R2, 's2r_received', 3.5);
  add(R2, 's2r_pending', 2.5);
  add(PF, 's3z_receipt', 2.5);
  // Act 3 — reconnect and settle for real on Stellar testnet
  add(PF, 's4a_reconnecting', 1.5);
  add(PF, 's4b_settled', 6.0);

  const concatList = path.join(ROOT, 'seq.txt');
  fs.writeFileSync(
    concatList,
    seq.map((s) => `file '${s.p}'\nduration ${s.dur}`).join('\n') +
      `\nfile '${seq[seq.length - 1].p}'\n`
  );

  const out = path.join(ROOT, 'payflex_offline_demo.mp4');
  execSync(
    `ffmpeg -y -f concat -safe 0 -i ${concatList} ` +
      `-vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0x0B1220,fps=30,format=yuv420p" ` +
      `-c:v libx264 -preset medium -crf 20 ${out}`,
    { stdio: 'inherit' }
  );
  console.log('VIDEO ' + out);

  // Side-by-side composites of the two devices for key beats.
  const pairs = [
    [path.join(R1, 's1r_qr_05.png'), path.join(PF, 's2a_scanning_1.png'), 'sbs_offer_scan.png'],
    [path.join(R2, 's2r_received.png'), path.join(PF, 's3z_receipt.png'), 'sbs_payoff.png'],
  ];
  for (const [a, b, name] of pairs) {
    const outPng = path.join(ROOT, name);
    execSync(
      `ffmpeg -y -i ${a} -i ${b} ` +
        `-filter_complex "[0]scale=540:1170[a];[1]scale=540:1170[b];[a][b]hstack" ` +
        `${outPng}`,
      { stdio: 'inherit' }
    );
    console.log('SBS ' + outPng);
  }

  // Verification manifest — everything a reviewer needs to check it's real.
  const settlement = JSON.parse(
    fs.readFileSync(path.join(PAY, 'settlement.json'), 'utf8')
  );
  const manifest = {
    ...settlement,
    explorerUrl: `https://stellar.expert/explorer/testnet/tx/${settlement.hash}`,
    horizonUrl: `https://horizon-testnet.stellar.org/transactions/${settlement.hash}`,
    note: 'All protocol steps executed by the app\'s real code (PaymentProtocol, OfflineReserveService, FountainCoder, AnimatedOpticalQr). Transport rendered to video instead of photons; QR frames decoded from rendered pixels with jsQR. Settlement is a real Stellar testnet transaction.',
  };
  fs.writeFileSync(
    path.join(ROOT, 'demo_manifest.json'),
    JSON.stringify(manifest, null, 2)
  );
  console.log('MANIFEST ' + path.join(ROOT, 'demo_manifest.json'));
}

const [cmd] = process.argv.slice(2);
if (cmd === 'decode-request') decodeQrFrames(path.join(REC, 'p1'), 'request_frames_decoded.txt');
else if (cmd === 'decode-confirmation') decodePayerConfirmation();
else if (cmd === 'video') buildVideo();
else {
  console.error('usage: node orchestrate.js decode-request|decode-confirmation|video');
  process.exit(1);
}
