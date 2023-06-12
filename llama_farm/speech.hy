"
Text to speech, using Bark.

Needs ~4GB VRAM. If you have a spare graphics card, set CUDA_VISIBLE_DEVICES appropriately.

See bark voices at https://suno-ai.notion.site/8b8e8749ed514b0cbf3f699013548683?v=bc67cff786b04b50b3ceb756fd05f68c
"

;; pip install simpleaudio play_sounds git+https://github.com/suno-ai/bark.git
;; on linux, simpleaudio requires alsa dev libs and python3 dev libs (probably)

(require hyrule.argmove [-> ->> as->])

(import os)
(import itertools)
(import numpy)
(import multiprocessing [Queue Process])
(import queue [Empty])

(setv (get os.environ "SUNO_USE_SMALL_MODELS") "True")
(import bark [SAMPLE_RATE generate-audio preload-models])

(import simpleaudio [play-buffer])
(import nltk.tokenize [sent-tokenize])


; import early
(preload-models)

(setv generate-timeout 60)

(defn _audio-loop [audio-queue]
  "Sequentially consume audio buffers from a queue until END."
  ;; I would rather use iter with a sentinel value here,
  ;; but can't do elementwise comparison with numpy arrays
  (while True
    (try
      (let [b (audio-queue.get :timeout generate-timeout)]
        ;(print "received " (type b))
        (if (isinstance b numpy.ndarray)
            (-> b
                (play-buffer 1 2 SAMPLE_RATE)
                (.wait-done))
            (break)))
      (except [Empty]
        (break)))))

(defn _sanitize-audio [audio-array]
  "Convert numpy array to wavlike format."
  ;; https://simpleaudio.readthedocs.io/en/latest/tutorial.html#using-numpy
  (-> audio-array
      (* 32767)
      (/ (max (abs audio_array)))
      (.astype numpy.int16)))

(defn _bark-fragment [text * queue [voice "v2/en_speaker_6"]]
  "Ideally speak about 13s (50 words) of text."
  (when text
    (-> text
        (generate-audio :history-prompt voice :silent True)
        (_sanitize-audio)
        (queue.put))))
    ;(print "sent" text)))

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

(defn bark [text [voice "v2/en_speaker_6"]]
  "Speak a longer passage of text."
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "false") ; since we're forking.
  (let [audio-queue (Queue)
        audio-loop (Process :target _audio-loop :args #(audio-queue))]
    (audio-loop.start)
    (-> text
        (sent-tokenize)
        (_bark-sentences :voice voice :queue audio-queue))
    (audio-queue.put "END")
    (audio-loop.join))
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "true"))
