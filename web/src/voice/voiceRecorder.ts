export interface VoiceRecorderChunk {
  sequence: number;
  sampleRate: number;
  channels: 1;
  audioBase64: string;
}

export interface VoiceRecorderOptions {
  onChunk: (chunk: VoiceRecorderChunk) => void;
  onError: (message: string) => void;
}

export class VoiceRecorder {
  private stream: MediaStream | null = null;
  private audioContext: AudioContext | null = null;
  private source: MediaStreamAudioSourceNode | null = null;
  private processor: ScriptProcessorNode | null = null;
  private sequence = 0;
  private started = false;

  constructor(private opts: VoiceRecorderOptions) {}

  get isRecording(): boolean {
    return this.started;
  }

  async start(): Promise<number> {
    if (this.started && this.audioContext) return this.audioContext.sampleRate;
    this.sequence = 0;
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
          channelCount: 1,
        },
      });
      this.audioContext = new AudioContext({ sampleRate: 48_000 });
      this.source = this.audioContext.createMediaStreamSource(this.stream);
      this.processor = this.audioContext.createScriptProcessor(4096, 1, 1);
      this.processor.onaudioprocess = (event) => this.handleAudio(event);
      this.source.connect(this.processor);
      this.processor.connect(this.audioContext.destination);
      this.started = true;
      return this.audioContext.sampleRate;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Microphone permission failed";
      this.stop();
      this.opts.onError(message);
      throw error;
    }
  }

  stop(): void {
    this.started = false;
    if (this.processor) {
      this.processor.onaudioprocess = null;
      this.processor.disconnect();
      this.processor = null;
    }
    this.source?.disconnect();
    this.source = null;
    void this.audioContext?.close();
    this.audioContext = null;
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
  }

  private handleAudio(event: AudioProcessingEvent): void {
    if (!this.started || !this.audioContext) return;
    const input = event.inputBuffer.getChannelData(0);
    const pcm = new Int16Array(input.length);
    for (let i = 0; i < input.length; i += 1) {
      const clamped = Math.max(-1, Math.min(1, input[i] ?? 0));
      pcm[i] = clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff;
    }
    this.opts.onChunk({
      sequence: this.sequence,
      sampleRate: this.audioContext.sampleRate,
      channels: 1,
      audioBase64: int16ToBase64(pcm),
    });
    this.sequence += 1;
  }
}

function int16ToBase64(pcm: Int16Array): string {
  const bytes = new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength);
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}
