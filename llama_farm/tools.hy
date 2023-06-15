"
Tools that generate text output for use by agents.

A tool must take a single string as its argument and return a single string output.
A tool's docstring is formatted using `tool-parser.describe` and stuffed into the prompt.
"
(require hyrule.argmove [-> ->> as->])

(import hyrule [inc])

(import itertools)
(import re)
(import subprocess)
(import json)

(import duckduckgo-search [DDGS])
(import lorem :as lorem-ipsum)
(import numexpr)
(import wikipedia :as wiki)
(import requests)
(import lxml)

(import llama-farm [texts])

;; Don't import functions here unless you want them to be available to the parser.
;; Even then, better to wrap them because the help text will be long and inappropriate.

;; TODO: incorporate summarization, but think about the plumbing first
;; TODO: maybe use guidance format and recursively parse?

;;; -----------------------------------------------------------------------------
;;; tool: command_string -> text
;;; A tool's docstring is formatted using `describe` and stuffed into the prompt.
;;; -----------------------------------------------------------------------------

(defn lorem [n]
  "returns n sentences of lorem ipsum text."
  (lorem-ipsum.get-sentence :count (numexpr.evaluate n)))

(defn calculator [expression]
  "POSIX bc with matlib - An arbitrary precision calculator language. Does not know mathematical constants.
returns the evaluated expression"
  (let [expr (re.sub "[\"']" "" expression)
        result (subprocess.run ["bc" "-lqi"]
                               :input (.encode expr)
                               :capture-output True)]
    (+ f"calculator {expression}: "
       (-> result.stdout
           (.decode)
           (.split)
           (get -1)))))

(defn fetch [url]
  "returns the text at a url."
  (.join "\n"
         [f"url {url}:"
          (texts.url->text url)]))
  
(defn wikipedia [topic [n 0]]
  "returns nth best Wikipedia summary on a topic."
  (try
    (let [pages (wiki.search topic)
          best (get pages n)
          summary (wiki.summary best :auto-suggest False)]
        (.join "\n"
               [f"wikipedia {best}:"
                summary
                "\nOther wikipedia pages:"
                (.join ", " pages)]))
    (except [wiki.exceptions.DisambiguationError]
      (wikipedia topic :n (inc n)))))
  
(defn search [topic]
  "returns an 'instant answer' DuckDuckGo web search."
  (with [ddgs (DDGS)]
    (let [answers (itertools.islice (ddgs.answers topic) 4)] 
      (.join "\n\n"
             [f"search {topic}:"
              #* (lfor a answers f"{(:url a)}\n{(:text a)}")]))))

(defn arxiv [topic]
  "returns the summary and details of the most relevant arXiv paper."
  ;; just the first entry.
  (.join "\n"
         [f"arxiv {topic}:"
          (-> topic
              (texts.arxiv->text)
              (.strip)
              (.split "\n\n")
              (get 0))]))

(defn news [[_ ""]]
  "returns recent world news articles from wikinews."
  (let [html (-> "https://en.wikinews.org/wiki/Main_Page"
                 (requests.get)
                 (. text)
                 (lxml.html.fromstring))
        element (html.get-element-by-id "MainPage_latest_news_text")
        items (-> element
                  (.text-content)
                  (.strip)
                  (.split "\n"))]
    (+ "news:\n"
       (.join "\n" (lfor i items f"- {i}")))))
  
(defn weather [[city ""]]
  "returns current weather for a city from `wttr.in`."
  (-> f"https://wttr.in/{city}?format=2"
      (texts.url->text) 
      (.strip)))

(defn city [[_ ""]]
  "returns what city the user is located in."
  (location "city"))

(defn location [[item "city"]]
  "returns the user's location: city, zip, region, latitude, longitude, etc."
  (let [loc (-> f"http://ip-api.com/json"
                (texts.url->text)
                (json.loads))
        _zip (:zip loc "unknown zip") 
        city (:city loc "unknown city") 
        region (:regionName loc "unknown region") 
        country (:country loc "unknown country") 
        lat (:lat loc "unknown latitude") 
        lon (:lon loc "unknown longitude")] 
    (if (in item loc)
        f"{item}: {(get loc item)}"
        f"( {_zip} {city} {region} {country} [{lat} {lon}] )")))

;; TODO: url, youtube summary - how to close over llm?
