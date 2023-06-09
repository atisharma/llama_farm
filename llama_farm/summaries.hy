"
The summarization functions take longer text and produce summary text,
bullet points, or a topic from it.

Syntax:
```
(text-reducer bot text :max-token-length 750 :max-depth 5)
```

Parameters:
- bot: The name of the language model defined in the config
- text: The longer text to be reduced to shorter summary text or
  bullet points.
- max-token-length: The maximum length of the text in tokens to be
  reduced to. Default is 750.
- max-depth (for recursive reducers only): The maximum depth of
  recursion for the text to be reduced to the desired length. Default
  is 5.

Return:
- Depending on the function called, `text-reducer` returns the summary
  text, bullet points, or topic of the text (all as a string).
"

(require hyrule.argmove [-> ->> as->])
(import hyrule [inc])

(import functools [partial])

(import transformers [AutoTokenizer])

(import langchain.text-splitter [RecursiveCharacterTextSplitter])

(import .utils [config params tee])
(import .guides [model text->summary text->points text->topic])
(import .interface [info error status-line])


(setv tokenizer (AutoTokenizer.from_pretrained (config "storage" "tokenizer")))

;;; -----------------------------------------------------------------------------
;;; Text handling and high-order functions
;;; -----------------------------------------------------------------------------

(defn token-length [text]
  "The length of the text in tokens."
  (-> text
      (tokenizer)
      (:input-ids)
      (len)))

(defn fragment [text [chunk-size 1000]]
  "Split a long text into a list of paragraphs of max length."
  (let [doc-splitter (RecursiveCharacterTextSplitter.from-huggingface-tokenizer
                       :tokenizer tokenizer
                       :chunk-size chunk-size
                       :chunk-overlap (// chunk-size 10))]
    (->> [text]
         (doc-splitter.create-documents)
         (map (fn [d] (. d page-content)))
         (list))))
  
(defn reduce-oneshot [f bot text]
  "Split a text into fragments and reduce each part by applying `f`.
Join them together at the end."
  (let [reducer (partial f bot)
        chunk-size (config "summary-chunk-size")]
    (->> text
         (fragment :chunk-size chunk-size)
         (map reducer)
         (.join "\n\n"))))

(defn reduce-recursive [f bot text
                        [max-token-length 750]
                        [max-depth 5]
                        [depth 0]
                        [reduction Inf]]
  "Summarize down to below specified token length by applying `f` recursively.
Stop at maximum recursion depth or when the reduction ratio is inadequate."
  (let [l (token-length text)]
    (info f"recursion depth {depth}, reduction {reduction :4.2f}, {l} tokens -> {max-token-length}...")
    (if (and (> l max-token-length)
             (< depth max-depth)
             (> reduction 1.2))
        (let [reduced-text (reduce-oneshot f bot text)
              reduced-length (token-length reduced-text)]
          (reduce-recursive f bot reduced-text
                            :max-token-length max-token-length
                            :max-depth max-depth
                            :depth (inc depth)
                            :reduction (/ l reduced-length)))
        text)))

;;; -----------------------------------------------------------------------------
;;; Reducers (for text well within context length)
;;; -----------------------------------------------------------------------------

(defn summarize-fragment [bot text]
  "Summarize a piece of text that fits within the context length.
Fall back to bullet points on failure, which seems more reliable."
  (if (.strip text)
      (try
        (:result ((text->summary) :input text :llm (model bot)))
        (except [ValueError]
          (error "Summarization failed, trying points extraction.")
          (error f"Input text: {text}")
          (points-fragment bot text)))
      ""))
  
(defn points-fragment [bot text]
  "Extract points from a piece of text that fits within the context length."
  (if (.strip text)
      (:result ((text->points) :input text :llm (model bot)))
      ""))

(defn topic-fragment [bot text]
  "Extract the topic from a piece of text that fits within the context length."
  (if (.strip text)
      (:result ((text->topic) :input text :llm (model bot)))
      ""))
  
;;; -----------------------------------------------------------------------------
;;; Recursive reducers (for text beyond context length, using divide-and-conquer)
;;; -----------------------------------------------------------------------------

(defn summarize [bot text [max-token-length 750] [max-depth 5]]
  "Recursively reduce to a summary paragraph."
  (reduce-recursive summarize-fragment
                    bot
                    text
                    :max-token-length max-token-length
                    :max-depth max-depth))

(defn points [bot text [max-token-length 750] [max-depth 5]]
  "Recursively reduce to bullet points."
  (reduce-recursive points-fragment
                    bot
                    text
                    :max-token-length max-token-length
                    :max-depth max-depth))

(defn summarize-hybrid [bot text [max-token-length 750]]
  "Recursively reduce to a summary paragraph via bullet points."
  (->> text
       (points bot :max-token-length (* 5 max-token-length))
       (summarize bot :max-token-length max-token-length)))

(defn topic [bot text [max-token-length 750] [max-depth 5]]
  "Recursively reduce to bullet points then determine a topic."
  (->> text
    (points bot :max-token-length max-token-length :max-depth max-depth)
    (topic-fragment bot))) 
