"
Text to speech, using Bark or Balacoon.

"

;; pip install simpleaudio play_sounds
;; on linux, simpleaudio requires alsa dev libs and python3 dev libs (probably)

(require hyrule.argmove [-> ->> as->])

(import numpy)
(import queue [Empty])

(import simpleaudio [play-buffer])


(setv generate-timeout 60)


(defn _audio-loop [audio-queue sample-rate]
  "Sequentially consume audio buffers from a queue until END."
  ;; I would rather use iter with a sentinel value here,
  ;; but can't do elementwise comparison with numpy arrays
  (while True
    (try
      (let [b (audio-queue.get :timeout generate-timeout)]
        ;(print "received " (type b))
        (if (isinstance b numpy.ndarray)
            (-> b
                (play-buffer 1 2 sample-rate)
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
