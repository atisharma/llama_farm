
(require hyrule.argmove [-> ->>])

(import json)
(import re)
(import pathlib [Path])

(import readline)

(setv re-parser (re.compile r"([^\n][ \w]*): "))


(defn rlinput [prompt [prefill ""]]
  (readline.set_startup_hook (fn [] (readline.insert_text prefill)))
  (try
    (input prompt)
    (finally
      (readline.set_startup_hook))))

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
    (json.dump obj f :indent 4)))

(defn slurp [fname]
  "Read a text file."
  (let [path (Path fname)]
    (when (path.exists)
      (path.read-text))))

(defn dprint [#* args]
  "Pretty print a bunch of args."
  (import rich)
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

(defn ->conclusion [text]
  "Extract just the last section of a reply string."
  (-> text
      (.split ":")
      (get -1)
      (.strip)))

(defn ->dict [text]
  "Split output into a dictionary with a key for each section of a reply string."
  (let [pairs (->> text
                   (re-parser.split)
                   (filter None))]
    (dfor [k v] (zip pairs pairs)
       (.strip (k.lower)) (.strip v))))
  
(defn ->text [plan]
  "Turn a plan dict into text."
  (.join "\n"
         (lfor [k v] (.items plan)
               f"{(k.upper)}: {v}")))
