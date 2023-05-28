"
Functions that relate to output on the screen.
"

(require hyrule.argmove [-> ->> as->])

(import hashlib [md5])

(import rich.console [Console])
(import rich.padding [Padding])
(import rich.markdown [Markdown])
(import rich.columns [Columns])
(import rich.table [Table])
(import rich.text [Text])
(import rich.progress [track])
(import rich.color [ANSI_COLOR_NAMES])


(setv console (Console :highlight None))
(setv colors (list (.keys ANSI_COLOR_NAMES)))
(setv render-markdown True)


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
  "Max over length of bot names, for use in chat formatting."
  (max 1 1 #* (lfor m chat-history (len (:bot m)))))

(defn format-msg [message margin]
  "Format a chat message for display."
  (let [l (-> message
              (:bot)
              (.capitalize)
              (+ ":"))
        content (-> message
                    (:content)
                    (.strip))]
                    ;(.replace "\n" "\n\n"))]
    f"{l :<{(+ 1 margin)}} {(.strip (:content message))}"))

(defn toggle-markdown []
  "Toggle the rendering of markdown in output."
  (global render-markdown)
  (setv render-markdown (not render-markdown)))

(defn sanitize [s]
  "Prepare a generic string for markdown rendering."
  ;; Markdown swallows single newlines.
  ;; and defines the antipattern of preserving them with a double space.
  (.replace s "\n" "  \n"))

(defn print-chat-history [chat-history [tokens None]]
  "Format and print the chat history to the screen."
  (let [margin (get-margin chat-history)]
    (console.rule)
    (console.print "Chat history:" :style "green italic")
    (console.print)
    (for [msg chat-history]
      (print-message msg margin :left-padding 4))
    (when tokens
      (console.print f"History uses ~{tokens} tokens." :style "green italic"))
    (console.rule)))

(defn info [s [style "green italic"]]
  "Print an information string to the screen."
  (-> s
      (sanitize)
      (Markdown)
      (Padding #(0 2 0 0))
      (console.print :justify "left" :style style)))

(defn error [s [style "red italic"]]
  "Print an error string to the screen."
  (-> s
      (sanitize)
      (Markdown)
      (Padding #(0 2 0 0))
      (console.print :justify "left" :style style)))

(defn exception []
  "Formats and prints the current exception."
  (console.print-exception))

(defn bot-color [bot]
  "The signature color of the bot, derived from its name."
  (let [bot (.capitalize bot)
        i (-> (bot.encode "utf-8")
              (md5)
              (.hexdigest)
              (int 16)
              (% 222)
              (+ 1))]
    (get colors i)))

(defn print-message [msg margin [left-padding 0]]
  "Format and print a message to the screen."
  (let [bot (.capitalize (:bot msg))
        color (bot-color bot)
        output (Table :padding [0 1 0 left-padding]
                      :expand True
                      :show-header False
                      :show-lines False
                      :box None)]
    (.add-column output :min-width margin)
    (.add-column output :ratio 1 :overflow "fold")
    (.add-row output f"[bold {color}]{bot}:[/bold {color}]"
              (if render-markdown
                  (Markdown (sanitize (:content msg)))
                  (:content msg)))
    (console.print output :justify "left")))

(defn print-last-message [chat-history margin]
  (-> chat-history
    (get -1)
    (print-message margin)))

(defn print-sources [docs]
  "Print relevant document metadata from a list of docs."
  (console.rule)
  (info "Sources:")
  (for [d docs]
    (let [page f"{(:page d.metadata "")}"
          source (:source d.metadata "unknown source")]
      (console.print " - " source (if page f" (p{page})" "")
                    :style "green")))
  (console.rule))

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

(defn spinner-context [s]
  (console.status (Text s :style "italic green")
                  :spinner "dots12"))  

(defn tabulate [rows headers
                [styles None]
                [title None]]
  "Return a rich table object from a list of lists (rows) and a list (headers)."
  (let [table (Table :title title :row-styles styles)]
    (for [h headers]
      (.add-column table h))
    (for [r rows]
      (.add-row table #* r))
    (console.print table :style "green")))
