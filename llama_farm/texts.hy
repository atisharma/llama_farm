"
Functions that produce strings from sources.
"

(require hyrule.argmove [-> ->>])

(import datetime [datetime timezone])

(import requests)
(import markdownify [markdownify])
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
  (let [transcript (.get-transcript YouTubeTranscriptApi youtube-id)
        formatter (TextFormatter)
        text (.format_transcript formatter transcript)]
    (if punctuate
        (do
          ; import here because not everyone will want to spend the VRAM.
          (import deepmultilingualpunctuation [PunctuationModel])
          (.restore-punctuation (PunctuationModel) text))
        text)))

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
