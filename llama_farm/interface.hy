(require hyrule.argmove [-> ->> as->])

(import functools [partial])

(import rich.console [Console])
(import rich.padding [Padding])
(import rich.markdown [Markdown])
(import rich.columns [Columns])
(import rich.table [Table])
(import rich.color [ANSI_COLOR_NAMES])


(setv console (Console :highlight None))
(setv colors (list (.keys ANSI_COLOR_NAMES)))
(setv render-markdown True)

;; TODO: "page" for chat data
;; TODO: left column for prompts
;; TODO: logging display
;; TODO: status line


(defn banner []
  (console.clear)
  (setv banner-text r"  _ _                             ___                   :
 | | |                           / __)                  :
 | | | _____ ____  _____ _____ _| |__ _____  ____ ____  :
 | | |(____ |    \(____ (_____|_   __|____ |/ ___)    \ :
 | | |/ ___ | | | / ___ |       | |  / ___ | |   | | | |:
  \_)_)_____|_|_|_\_____|       |_|  \_____|_|   |_|_|_|:
 :")
  (lfor [l c] (zip (.split banner-text ":")
                   ["#11FF00" "#33DD00" "#33BB00" "#339900" "#337720" "#227799" "#2288FF" "#2288FF"])
        (console.print l
                       :end None
                       :style f"bold {c}"
                       :overflow "crop"))
  (console.print "[default]"))

(defn clear []
  (console.clear))
  
(defn _set-width [line]
  (try
    (let [arg (get (.partition line " ") 2)]
      (global console)
      (setv console (Console :highlight None :width (int arg)))
      "")
    (except [[IndexError ValueError]]
      "[red]Bad console width value.[/red]")))

(defn set-width [line]
  (console.print (_set-width line)))
    
(defn get-margin [chat-history]
  "Max over length of personality names, for use in chat formatting."
  (max 1 1
       #* (lfor m chat-history (len (:personality m)))))

(defn format-msg [message margin]
  "Format a chat message for display."
  (let [l (-> message
              (:personality)
              (.capitalize)
              (+ ":"))
        content (-> message
                    (:content)
                    (.strip))]
                    ;(.replace "\n" "\n\n"))]
    f"{l :<{(+ 1 margin)}} {(.strip (:content message))}"))

(defn toggle-markdown []
  (global render-markdown)
  (setv render-markdown (not render-markdown)))

(defn print-chat-history [chat-history]
  (let [margin (get-margin chat-history)]
    (console.rule)
    (console.print "[italic]Chat history:[/italic]")
    (for [msg chat-history]
      (print-message msg margin :left-padding 4))
    (console.rule)))

(defn info [s]
  (-> s
    (Markdown)
    (Padding #(0 2 0 0))
    (console.print :justify "left")))

(defn print-message [msg margin [left-padding 0]]
  (let [personality (.capitalize (:personality msg))
        color (get colors (+ 1 (% (hash (:personality msg)) 220)))
        output (Table :padding [0 1 0 left-padding]
                      :expand True
                      :show-header False
                      :show-lines False
                      :box None)
        content (.replace (:content msg) "\n" "\n\n")]
    (.add-column output :min-width margin)
    (.add-column output :ratio 1 :overflow "fold")
    (.add-row output f"[bold {color}]{(:personality msg)}:[/bold {color}]"
              (if render-markdown
                  (Markdown (:content msg))
                  (:content msg)))
    (console.print output :justify "left")))

  ;(-> msg))
      ;(format-msg margin)))
      ;(Markdown)
      ;(Padding #(0 2 0 0))
      ;(console.print :justify "left")))

(defn format-sources [response]
  "Format a response with sources as a string."
  (.join "\n"
    [(:result response)
     "\n"
     #* (sfor d (:source-documents response)
              (let [page (str (:page d.metadata ""))]
                (+ "- "
                   (:source d.metadata "unknown source")
                   (if page f" (p{page})" ""))))]))
