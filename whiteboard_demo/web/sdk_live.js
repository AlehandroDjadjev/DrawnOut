// SDK Live (Browser) — mirrors backend/templates/index.html SDK block.
// Exposes window.startSdkLive(oneTurn) and window.stopSdkLive().

import { GoogleGenAI, Modality } from 'https://esm.sh/@google/genai';

let sdkAudioCtx = null;
let sdkMicStream = null;
let sdkSourceNode = null;
let sdkProcessor = null;
let sdkSession = null;
let sdkPlayQueue = [];

function baseLessons(){
  try {
    let v = (window.__ASSISTANT_API_BASE || '').trim();
    if (!v){ v = location.origin + '/api/lessons'; }
    // normalize: strip trailing slashes
    while (v.endsWith('/')) v = v.slice(0, -1);
    // If someone passed root or /api, make it /api/lessons
    if (v.endsWith('/api')) v = v + '/lessons';
    if (!/\/api\/lessons$/i.test(v)) v = v + '/api/lessons';
    return v;
  } catch { return location.origin + '/api/lessons'; }
}

function api(path){
  const b = baseLessons();
  return b + path; // e.g., .../api/lessons + /token/ => .../api/lessons/token/
}

function base64ToInt16(b64){
  const bin = atob(b64);
  const len = bin.length;
  const bytes = new Uint8Array(len);
  for (let i=0;i<len;i++){ bytes[i] = bin.charCodeAt(i); }
  return new Int16Array(bytes.buffer);
}

async function playPCM16(int16, sampleRate){
  if (!sdkAudioCtx) sdkAudioCtx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: 'interactive' });
  try{ await sdkAudioCtx.resume(); }catch{}
  const f32 = new Float32Array(int16.length);
  for (let i=0;i<int16.length;i++){ f32[i] = Math.max(-1, Math.min(1, int16[i] / 0x8000)); }
  const buffer = sdkAudioCtx.createBuffer(1, f32.length, sampleRate);
  buffer.getChannelData(0).set(f32);
  const src = sdkAudioCtx.createBufferSource();
  src.buffer = buffer;
  src.connect(sdkAudioCtx.destination);
  const when = sdkPlayQueue.length ? sdkPlayQueue[sdkPlayQueue.length-1].when + sdkPlayQueue[sdkPlayQueue.length-1].buffer.duration : (sdkAudioCtx.currentTime + 0.02);
  sdkPlayQueue.push({ when, buffer });
  src.start(when);
  src.onended = () => { sdkPlayQueue.shift(); };
}

function int16ToBase64(int16){
  const u8 = new Uint8Array(int16.buffer);
  let b64 = '';
  for (let i=0;i<u8.length;i+=0x8000){ b64 += String.fromCharCode.apply(null, u8.subarray(i, i+0x8000)); }
  return btoa(b64);
}

async function sdkStart(oneTurn){
  try{
    const t = await fetch(api('/token/')).then(r=>r.json()).catch(()=>({}));
    if(!t || !t.token){ throw new Error('No token'); }
    if (!GoogleGenAI || !Modality){ throw new Error('SDK unavailable'); }

    const ai = new GoogleGenAI({ apiKey: t.token });
    sdkSession = await ai.live.connect({
      model: 'gemini-2.0-flash-live-001',
      config: { responseModalities: [Modality.AUDIO], systemInstruction: 'You are a friendly voice assistant.' },
      callbacks: {
        onopen(){
          try{ sdkSession?.sendRealtimeInput({ text: 'Hello! Please respond briefly.' }); }catch{}
          setTimeout(() => { try{ sdkSession?.sendRealtimeInput({ text: 'Please reply now to confirm audio.' }); }catch{} }, 1000);
        },
        onmessage(msg){
          if (msg?.data){ try{ playPCM16(base64ToInt16(msg.data), 24000); }catch{} }
          if (msg?.serverContent?.turnComplete && oneTurn){ try{ window.__afterLiveTurn && window.__afterLiveTurn(); }catch{} }
        },
        onerror(){},
        onclose(){ if (oneTurn) { try{ window.__afterLiveTurn && window.__afterLiveTurn(); }catch{} } }
      }
    });

    // Mic → 16k PCM16 mono → base64
    sdkAudioCtx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: 'interactive' });
    try{ await sdkAudioCtx.resume(); }catch{}
    sdkMicStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation:true, noiseSuppression:true, autoGainControl:true } });
    sdkSourceNode = sdkAudioCtx.createMediaStreamSource(sdkMicStream);
    const silent = sdkAudioCtx.createGain(); silent.gain.value = 0.0;
    const workletOk = !!(sdkAudioCtx.audioWorklet && sdkAudioCtx.audioWorklet.addModule);
    if (workletOk){
      const workletUrl = URL.createObjectURL(new Blob([`
class PCM16Worklet extends AudioWorkletProcessor {
  constructor(){ super(); this._carry = new Float32Array(0); }
  process(inputs){
    const inputCh = inputs[0][0]; if (!inputCh) return true;
    const sr = sampleRate || 48000; const target = 16000; const ratio = sr / target;
    const samples = new Float32Array(this._carry.length + inputCh.length);
    samples.set(this._carry, 0); samples.set(inputCh, this._carry.length);
    const outLen = Math.floor(samples.length / ratio);
    const i16 = new Int16Array(outLen);
    for (let i=0;i<outLen;i++){ let s = samples[Math.floor(i*ratio)]; s = Math.max(-1, Math.min(1, s)); i16[i] = s<0 ? s*0x8000 : s*0x7FFF; }
    const remainStart = Math.floor(outLen * ratio);
    this._carry = samples.subarray(remainStart).slice();
    this.port.postMessage(i16.buffer, [i16.buffer]);
    return true;
  }
}
registerProcessor('pcm16-worklet', PCM16Worklet);
`], { type: 'application/javascript' }));
      await sdkAudioCtx.audioWorklet.addModule(workletUrl);
      sdkProcessor = new AudioWorkletNode(sdkAudioCtx, 'pcm16-worklet');
      sdkProcessor.port.onmessage = (e) => {
        try{ const int16 = new Int16Array(e.data); const b64 = int16ToBase64(int16); sdkSession?.sendRealtimeInput({ audio: { data: b64, mimeType: 'audio/pcm;rate=16000' } }); }catch{}
      };
      sdkSourceNode.connect(sdkProcessor).connect(silent).connect(sdkAudioCtx.destination);
    } else {
      const script = (sdkProcessor = sdkAudioCtx.createScriptProcessor(4096, 1, 1));
      script.onaudioprocess = (e) => {
        if (!sdkSession) return;
        const f32 = e.inputBuffer.getChannelData(0);
        const i16 = new Int16Array(f32.length);
        for (let i=0;i<f32.length;i++){ let s = Math.max(-1, Math.min(1, f32[i])); i16[i] = s<0 ? s*0x8000 : s*0x7FFF; }
        const b64 = int16ToBase64(i16);
        try{ sdkSession.sendRealtimeInput({ audio: { data: b64, mimeType: 'audio/pcm;rate=16000' } }); }catch{}
      };
      sdkSourceNode.connect(script).connect(silent).connect(sdkAudioCtx.destination);
    }
  }catch(e){ /* ignore; UI should handle errors */ }
}

async function sdkStop(){
  try{ sdkProcessor && sdkProcessor.disconnect(); }catch{}
  try{ sdkSourceNode && sdkSourceNode.disconnect(); }catch{}
  try{ sdkMicStream && sdkMicStream.getTracks().forEach(t=>t.stop()); }catch{}
  try{ sdkSession && sdkSession.close(); }catch{}
  try{ sdkAudioCtx && sdkAudioCtx.close(); }catch{}
  sdkProcessor = null; sdkSourceNode = null; sdkMicStream = null; sdkSession = null; sdkAudioCtx = null; sdkPlayQueue = [];
}

try{
  window.startSdkLive = async function(oneTurn){
    await sdkStart(!!oneTurn);
  };
  window.stopSdkLive = async function(){
    await sdkStop();
  };
}catch{}


