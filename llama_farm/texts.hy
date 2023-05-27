"
Functions that produce strings from sources.
"

(require hyrule.argmove [-> ->>])

(import requests)
(import markdownify [markdownify])
(import lxml)
(import lxml.html.clean [Cleaner])

(import youtube_transcript_api [YouTubeTranscriptApi])
(import youtube_transcript_api.formatters [TextFormatter])
(import deepmultilingualpunctuation [PunctuationModel])


(defn youtube->text [youtube-id [punctuate False]]
  "Load and punctuate youtube transcript as text.
   Youtube 'transcripts' are just a long list of words with no punctuation
   or identification of the speaker, so we apply a punctuation filter.
   This takes a fair amount of VRAM."
  (let [transcript (.get-transcript YouTubeTranscriptApi youtube-id)
        formatter (TextFormatter)
        text (.format_transcript formatter transcript)]
    (if punctuate
        (.restore-punctuation (PunctuationModel) text)
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
