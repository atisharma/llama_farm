
(require hyrule.argmove [-> ->>])

(import json)
(import pathlib [Path])


(defn load [fname]
  "Read a json file."
  (with [f (open fname
                 :mode "r"
                 :encoding "UTF-8")]
    (json.load f)))


(defn save [obj fname]
  "Write an object as a json file."
  (with [f (open fname
                 :mode "w"
                 :encoding "UTF-8")]
    (json.dump obj f)))


(defn slurp [fname]
  "Read a text file."
  (let [p (Path fname)]
    (when (path.exists)
      (path.read-text))))


(defn dprint [#* args]
  "Pretty print a bunch of args."
  (for [x args]
    (rich.print (* "=" 80))
    (rich.print x))
  (rich.print (* "=" 80)))


(defn get-response [response]
  (get response "choices" 0 "text"))


(defn get-alpaca-response-text [response]
  "Get the response text of an Alpaca type response."
  (-> response
    (.split "# Response:")
    (get -1)
    (.strip)))
