"
This module provides functions that generate strings from a variety of sources.
"

(require hyrule.argmove [-> ->>])

(import functools [reduce])

(import datetime [datetime timezone])

(import requests)
(import markdownify [markdownify])
(import locale)
(import lxml)
(import lxml.html.clean [Cleaner])

(import youtube_transcript_api [YouTubeTranscriptApi])
(import youtube_transcript_api.formatters [TextFormatter])

(import langchain.utilities [ArxivAPIWrapper WikipediaAPIWrapper])
(import langchain.utilities.duckduckgo_search [DuckDuckGoSearchAPIWrapper])


(defn youtube->text [youtube-id [punctuate False]]
  "Load (and optionally punctuate) youtube transcript as text.
   Youtube 'transcripts' are normally just a long list of words with no
   punctuation or identification of the speaker.
   We can apply punctuation filter, but this takes VRAM and requires pytorch.
   !!! WARNING !!!
   This takes a fair amount (1-2G) of VRAM.
   !!! WARNING !!!"
  ;; Defaults to user's locale, this may not be desirable for summarization
  (let [languages [(get (locale.getlocale) 0) "en" "en-GB"]
        avail-transcripts (.list-transcripts YouTubeTranscriptApi youtube-id)
        transcript (.fetch (.find-transcript avail-transcripts languages))
        formatter (TextFormatter)
        text (.format_transcript formatter transcript)]
    (if punctuate
        (do
          ; import here because not everyone will want to spend the VRAM.
          (import deepmultilingualpunctuation [PunctuationModel])
          (.restore-punctuation (PunctuationModel) text))
        text)))

(defn youtube-title->text [youtube-id]
  "Return the title of the youtube video."
  (let [url f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={youtube-id}&format=json"
        response (.get requests url)]
    (if response.ok
        (let [data (.json response)]
          (:title data "No title provided"))
        (.raise_for_status response))))

(defn url->text [url]
  "Fetch a URL's content as cleaned markdown text."
  (let [html (-> url
                 (requests.get)
                 (. text))
        cleaner (Cleaner :javascript True :style True)]
    (-> html
        (lxml.html.fromstring html)
        (cleaner.clean_html)
        (lxml.html.tostring)
        (markdownify :heading-style "ATX" :strip "style"))))

(defn ddg->text [topic]
  "Get the DuckDuckGo summary on a topic (as text)."
  (.run (DuckDuckGoSearchAPIWrapper) topic))

(defn arxiv->text [topic]
  "Get relevant arxiv summaries on a topic (as text)."
  (.run (ArxivAPIWrapper) topic))

(defn wikipedia->text [topic]
  "Get relevant Wikipedia summaries on a topic (as text)."
  (.run (WikipediaAPIWrapper) topic))

(defn today->text [[fmt "%Y-%m-%d"]]
  "Today's date (as text)."
  (.strftime (datetime.today) fmt))

(defn now->text []
  "Current timestamp in isoformat (as text) with timezone."
  (-> timezone.utc
      (datetime.now)
      (.astimezone)
      (.isoformat)))
