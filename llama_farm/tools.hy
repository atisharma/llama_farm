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

;;; Don't import functions here unless you want them to be available to the parser.
;;; Even then, better to wrap them because the help text will be long and inappropriate.

;;; TODO: incorporate summarization, but think about the plumbing first

;;; -----------------------------------------------------------------------------
;;; tool: command_string -> text
;;; A tool's docstring is formatted using `describe` and stuffed into the prompt.
;;; -----------------------------------------------------------------------------

(defn lorem [n]
  "Generate n sentences of lorem ipsum text.
Syntax: [[lorem l]]
Parameters: l, an integer that is the number of sentences to be generated."
  (lorem-ipsum.get-sentence :count (numexpr.evaluate n)))

(defn calculator [s]
  "POSIX bc with matlib - An arbitrary precision calculator language. Does not know mathematical constants.
Syntax: [[calculator expression]]
Parameters: expression to be evaluated.
Example: [[calculator 3 * 9]] returns 27."
  (let [expr (re.sub "[\"']" "" s)
        result (subprocess.run ["bc" "-lqi"]
                               :input (.encode expr)
                               :capture-output True)]
    (+ f"(calculator {s}) "
       (-> result.stdout
           (.decode)
           (.split)
           (get -1)))))

(defn url [url]
  "Read the text at a url.
Syntax: [[url url-to-read]]
Parameters: the url to read.
Example: [[url https://www.example.com]]"
  (.join "\n"
         [f"(url {url})"
          (texts.url->text url)]))
  
(defn wikipedia [topic [index 0]]
  "Get current facts from Wikipedia summaries.
Syntax: [[wikipedia topic]]
Parameters: the search topic.
Example call: [[wikipedia Example topic]]"
  ;; just the first entry.
  (try
    (let [pages (wiki.search topic)
          best (get pages index)
          summary (wiki.summary best :auto-suggest False)]
        (.join "\n"
               [f"(wikipedia {best})"
                summary
                "\nOther wikipedia pages:"
                (.join ", " pages)]))
    (except [wiki.exceptions.DisambiguationError]
      (wikipedia topic :index (inc index)))))
  
(defn search [topic]
  "Do an 'instant answer' DuckDuckGo web search.
Syntax: [[search topic]]
Parameters: the short search phrase.
Example: [[search Famous Person or Event]]"
  (with [ddgs (DDGS)]
    (let [answers (itertools.islice (ddgs.answers topic) 4)] 
      (.join "\n\n"
             [f"(search {topic})"
              #* (lfor a answers f"{(:url a)}\n{(:text a)}")]))))

(defn arxiv [topic]
  "Get the summary and details of the most relevant arXiv paper.
Syntax: [[arxiv topic]]
Parameters: the arXiv paper number or narrow search phrase.
Example: [[arXiv 2205.02677]]"
  ;; just the first entry.
  (.join "\n"
         [f"(arxiv {topic})"
          (-> topic
              (texts.arxiv->text)
              (.strip)
              (.split "\n\n")
              (get 0))]))

(defn news [s]
  "Get recent news articles from wikinews.
Syntax: [[news]]
Parameters: the short search phrase.
Example: [[news]]"
  (let [html (-> "https://en.wikinews.org/wiki/Main_Page"
                 (requests.get)
                 (. text)
                 (lxml.html.fromstring))
        element (html.get-element-by-id "MainPage_latest_news_text")
        items (-> element
                  (.text-content)
                  (.strip)
                  (.split "\n"))]
    (+ "[news]\n"
       (.join "\n" (lfor i items f"- {i}")))))
  
(defn weather [city]
  "Current weather for a city from `wttr.in`.
Syntax: [[weather city]]
Parameters: a city.
Example: [[weather Example_city]] tells you the weather in Example_city."
  (+ f"(weather {city}) "
     (-> f"https://wttr.in/{city}?format=2"
         (texts.url->text) 
         (.strip))))

(defn city [s]
  "Get what city the user is located in.
Syntax: [[city]]"
  (+ "(city) "
     (location "city")))

(defn location [s]
  "Get the user's location: city, zip, region, latitude, longitude, etc.
Syntax: [[location]] or [[location parameter]]
Example: [[location]] returns values for all parameters."
  (let [loc (-> f"http://ip-api.com/json"
                (texts.url->text)
                (json.loads))
        _zip (:zip loc "unknown zip") 
        city (:city loc "unknown city") 
        region (:regionName loc "unknown region") 
        country (:country loc "unknown country") 
        lat (:lat loc "unknown latitude") 
        lon (:lon loc "unknown longitude")] 
    (if (in s loc)
        f"(location {s}) {(get loc s)}"
        f"(location) {_zip}, {city}, {region}, {country}, [{lat}, {lon}]")))
