"
Wrap bark TTS and send to audio.

Bark needs ~4GB VRAM. If you have a spare graphics card, set CUDA_VISIBLE_DEVICES appropriately.

See bark voices at https://suno-ai.notion.site/8b8e8749ed514b0cbf3f699013548683?v=bc67cff786b04b50b3ceb756fd05f68c
"

;; pip install _sounds git+https://github.com/suno-ai/bark.git

(require hyrule.argmove [-> ->> as->])

(import os)
(import multiprocessing [Queue Process])

(setv (get os.environ "SUNO_USE_SMALL_MODELS") "True")
(import bark [SAMPLE_RATE generate-audio preload-models])
(import nltk.tokenize [sent-tokenize])

(import .audio [_audio-loop _sanitize-audio])


; import early
(preload-models)

(defn _bark-fragment [text * queue [voice "v2/en_speaker_6"]]
  "Ideally speak about 13s (50 words) of text."
  (when text
    (-> text
        (generate-audio :history-prompt voice :silent True)
        (_sanitize-audio)
        (queue.put))))
    ;(print "bark sent" text)))

(defn _bark-sentences [sentences * queue [buffer ""] [n 80] [voice "v2/en_speaker_6"]]
  "Speak groups of sentences of about n chars."
  (if sentences
    (let [first-sentence (get sentences 0)
          next-buffer (+ buffer " " first-sentence)]
      (cond
        ; flush the buffer
        (> (len buffer) n) (do
                             (_bark-fragment buffer :queue queue :voice voice)
                             (_bark-sentences sentences :queue queue :buffer "" :voice voice))
        ; flush the buffer if the next sentence is too long
        (> (len first-sentence) n) (do
                                     (_bark-fragment buffer :queue queue :voice voice)
                                     (_bark-sentences (cut sentences 1 None) :queue queue :buffer first-sentence :voice voice))
        ; shunt a sentence to the buffer
        :else (_bark-sentences (cut sentences 1 None) :queue queue :buffer next-buffer :voice voice)))
    ; flush the remaining bit
    (_bark-fragment buffer :queue queue :voice voice)))

(defn speak [text [voice "v2/en_speaker_6"]]
  "Speak a longer passage of text."
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "false") ; since we're forking.
  (let [audio-queue (Queue)
        audio-loop (Process :target _audio-loop :args #(audio-queue SAMPLE_RATE))]
    (audio-loop.start)
    (-> text
        (sent-tokenize)
        (_bark-sentences :voice voice :queue audio-queue))
    (audio-queue.put "END")
    (audio-loop.join))
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "true"))
