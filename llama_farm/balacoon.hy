"
Wrap balacoon TTS and send to audio.

Balacoon is pretty light.
Models and speakers available at https://huggingface.co/balacoon/tts

"

(import os)
(import multiprocessing [Queue Process])

(import balacoon-tts [TTS SpeechUtterance])
(import nltk.tokenize [sent-tokenize])
(import huggingface-hub [hf-hub-download])

(import .audio [_audio-loop _sanitize-audio])


(defn speak [text [model "en_us_cmuartic_jets_cpu.addon"] [speaker None]]
  "Speak a longer passage of text."
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "false") ; since we're forking.
  (hf-hub-download :repo_id "balacoon/tts"
                   :filename model
                   :local-dir "balacoon")
  (let [tts (TTS f"balacoon/{model}")
        speaker (or speaker (get (tts.get-speakers) -1))
        audio-queue (Queue)
        audio-loop (Process :target _audio-loop
                            :args #(audio-queue (tts.get-sampling-rate)))]
    (audio-loop.start)
    (for [t (sent-tokenize text)]
      ; per-sentence sounds smoother than streaming chunks.
      (audio-queue.put (tts.synthesize t speaker)))
    (audio-queue.put "END")
    (audio-loop.join))
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "true"))
