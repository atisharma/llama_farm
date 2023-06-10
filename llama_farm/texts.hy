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

(import wikipedia :as wiki)
(import arxiv)
(import youtube_transcript_api [YouTubeTranscriptApi])
(import youtube_transcript_api.formatters [TextFormatter])


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

(defn arxiv->text [topic [n 12]]
  "Get relevant arxiv summaries on a topic (as text)."
  (let [results (.results (arxiv.Search :query topic :max-results n))]
    (.join "\n\n---\n\n"
           (lfor paper results
                 (let [authors (.join ", " (map str paper.authors))]
                   f"**{paper.title}**
Authors: *{authors}*
Date: {paper.published}
{paper.entry_id}  DOI: {paper.doi}
Summary:
{paper.summary}")))))

(defn wikipedia->text [topic [index 0]]
  "Get the full Wikipedia page on a topic (as text)."
  (try
    (let [pages (wiki.search topic)
          best (get pages index)
          summary (wiki.summary best :auto-suggest False)
          page (wiki.page best :auto-suggest False)]
        (.join "\n"
               [f"Wikipedia: {page.title}"
                f"{page.url}"
                f"{page.content}"
                "\nOther wikipedia pages:"
                (.join ", " pages)]))
    (except [wiki.exceptions.DisambiguationError]
      (wikipedia topic :index (inc index)))))
  
(defn today->text [[fmt "%Y-%m-%d"]]
  "Today's date (as text)."
  (.strftime (datetime.today) fmt))

(defn now->text []
  "Current timestamp in isoformat (as text) with timezone."
  (-> timezone.utc
      (datetime.now)
      (.astimezone)
      (.isoformat)))
