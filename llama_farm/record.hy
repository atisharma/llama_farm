"
Speech to text, using faster-whisper.
"

(require hyrule.argmove [-> ->> as->])

(import sounddevice)
(import faster_whisper [WhisperModel])

;; see https://python-sounddevice.readthedocs.io/en/latest/
;; recording = sounddevice.rec(int(seconds * fs), samplerate=fs, channels=1)
;; sounddevice.wait()  # Wait until recording is finished


(defn _record-loop [record-queue record-key sample-rate * [duration 5]]
  "Record and enqueue audio segments until button is released."
  (while (keyboard.is-pressed record-key)
    ; use an InputStream
    (-> (sounddevice.rec (int (* sample-rate duration)) :samplerate sample-rate :channels 1 :blocking True)
        (.flatten)
        (record-queue.put))))
