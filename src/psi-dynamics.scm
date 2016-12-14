;
; psi-dynamics.scm
;
; OpenPsi dynamics control for Hanson robot

(use-modules (opencog) (opencog exec) (opencog openpsi) (opencog python))

; needed for nlp parsing
(use-modules (opencog nlp) (opencog nlp chatbot) (opencog nlp chatbot-psi))

; Param setting
(define valence-activation-level .5)

(define psi-verbose #t)
(define no-blender #f)

(define single-dimension-valence #t)

(if no-blender
	(python-eval "execfile('/usr/local/share/opencog/python/atomic-dbg.py')"))

(define prev-value-node (Concept "previous value"))
(define current-sentence-node (Concept "current sentence"))

; Temporary call needed to load dynamics code while it's in dev phase
(load-openpsi-in-development)

; Function called by OpenPsi when it believes expression command updates should
; occur based on event detection and subsequent OpenPsi variable updating
(define (psi-expression-callback)
	(define arousal (psi-get-arousal))
	(define pos-valence (psi-get-pos-valence))
	(define neg-valence (psi-get-neg-valence))
	;(if psi-verbose (display "psi-dynamics expression callback called\n"))

	; For now we are doing something simple - do a random positive or negative
	; expression based on valence and arousal.
	; Later arousal will be used to modulate intensity of the expression
	; Todo: How to handle when both pos and neg valence are high ? Expressing
	; both for now, which may or may not be a good thing, but probably
	; interesting nonetheless.
	(if (>= pos-valence valence-activation-level)
		(begin
			;( (do-catch do-random-positive-expression))
			(if psi-verbose
				(display "psi-dynamics: doing positive expression\n"))
			(if (not no-blender)
				(be-happy pos-valence)
				;(do-random-positive-expression)
			)
		)
	)
	(if (>= neg-valence valence-activation-level)
		(begin
			;( (do-catch do-random-negative-expression))
			(if psi-verbose
				(display "psi-dynamics: doing negative expression\n"))
			(if (not no-blender)
				(be-sad neg-valence)
				;(do-random-negative-expression)
			)
		)
	)

	; Update psi-emotion-states
	; Keeping it simple for now
	; For happy perhaps pos-valence * arousal or weighted average?
	; Todo: Map out other emotions
	(psi-set-value! psi-happy (* pos-valence arousal))
)

; Register the expression callback function with OpenPsi
(psi-set-expression-callback! psi-expression-callback)

; ------------------------------------------------------------------
; Functions to initiate random positive and negative expressions

; XXX FIXME -- this is hacky -- and has multiple design flaws.
; These are:
;
; * This should not use cog-evaluate! to force execution. Instead,
;   this should be placed in the action part of an open-psi rule.
;   Then, when that psi-rule triggers, the action will automatically
;   triggered, and the actin will be performed. No cog-execute! is
;   needed, because it will happen automatically.
;
; * This should used the defined predicates in express.scm, which
;   will automatically provide an appropriate, configurable, random
;   duration for the expression, instead of the hard-coded 8 seconds
;   below.
;
; * There are a hell of a lot more valencies than just "positive"
;   and "negative". Take a look at cfg-sophia.scm to see some of them:
;   these include: bored, sleeping, aroused, listening (attentive),
;   speaking (active). A full list of nine valencies are given in
;   the `README-affects.md` in the base directory.
(define (do-random-positive-expression intensity)
	 (cog-evaluate!
		 (Put (DefinedPredicate "Show facial expression")
			 (ListLink
				 (PutLink (DefinedSchemaNode "Pick random expression")
					 (ConceptNode "positive"))
				 (Number 8) (Number intensity)))))

(define (do-random-negative-expression intensity)
	 (cog-evaluate!
		 (Put (DefinedPredicate "Show facial expression")
			 (ListLink
				 (PutLink (DefinedSchemaNode "Pick random expression")
					 (ConceptNode "frustrated"))
				 (Number 8) (Number intensity)))))

(define (be-happy intensity)
	;(display "in (be-happy)\n")
	(cog-evaluate! (Put (DefinedPredicate "Show facial expression")
		(ListLink (Concept "happy") (Number 8) (Number intensity)))))

(define (be-sad intensity)
	;(display "in (be-sad)\n")
	(cog-evaluate! (Put (DefinedPredicate "Show facial expression")
		(ListLink (Concept "sad") (Number 8) (Number intensity)))))

; Temp error catching for when blender not running
(define (do-catch function . params)
	(catch #t
	  (lambda ()
		(apply function params))
	(lambda (key . parameters)
		(format (current-error-port)
				  "\nUncaught throw to '~a: ~a\n" key parameters)
		)
	)
)

; ------------------------------------------------------------------
; Create Monitored Events
(define new-face (psi-create-monitored-event "new-face"))
(define speech-giving-starts
	(psi-create-monitored-event "speech-giving-starts"))
(define positive-sentiment-dialog
	(psi-create-monitored-event "positive-sentiment-dialog"))
(define negative-sentiment-dialog
	(psi-create-monitored-event "negative-sentiment-dialog"))
; Using the self-model defined predicate for this instead
;(define loud-noise-event
;	(psi-create-monitored-event "loud-noise"))

; ------------------------------------------------------------------
; Event detection callbacks

; Callback function for positive and negative chat sentiment detection
(define (psi-detect-dialog-sentiment)
	(define current-input (get-input-sent-node))
	(define previous-input (psi-get-value current-sentence-node))
	;(format #t "current-input: ~a\n" current-input)
	(if (and (not (equal? current-input '()))
			 (not (equal? current-input previous-input)))
		; We have a new input sentence
		(begin
			;(if psi-verbose (format #t "\n* New input sentence detected *\n"))
			;(format #t "previous-input: ~a   current-input: ~a\n"
			;    previous-input current-input)
			(StateLink current-sentence-node current-input)
			; Check for positive and/or negative sentimement
			; Sentence sentiment is put in the atomspace as
			;   (Inheritance (Sentence "blah") (Concept "Positive")) or "Negative"
			;   or "Neutral"
			(let ((inher-super (cog-chase-link 'InheritanceLink 'ConceptNode
					current-input)))
				;(format #t "inher-super: ~a\n" inher-super)
				(for-each (lambda (concept)
							(if psi-verbose
								(format #t "Dialog sentiment detected: ~a\n"
									concept))
							(if (equal? concept (Concept "Positive"))
								(psi-set-event-occurrence!
									positive-sentiment-dialog))
							(if (equal? concept (Concept "Negative"))
								(psi-set-event-occurrence!
									negative-sentiment-dialog)))
						inher-super)))))

; Callback checks for both positive and negative sentiment
(psi-set-event-callback! psi-detect-dialog-sentiment)

; Callback for loud noise detected
; Using the self-model defined predicate for this instead of the below
;(define new-loud-noise? #f) ; indicates a loud noise just occurred
;(define (psi-check-for-loud-noise)
;	; This step is a temp hack for development purpose. Need to replace this
;	; with the method for actual event detection, which I think will be through
;	; ROS messaging.
;	(if new-loud-noise?
;		(begin
;			(psi-set-event-occurrence! loud-noise-event)
;			(set! new-loud-noise? #f))))

; Register the callback with the openpsi dynamics updater
;(psi-set-event-callback! psi-check-for-loud-noise)


;-------------------------------------
; Internal vars to physiology mapping

; PAU's
;(define pau-prefix-str "PAU: ")
; temp change for compatibility with psi graphing
(define pau-prefix-str psi-prefix-str)
(define (create-pau name initial-value)
	(define pau
		(Concept (string-append pau-prefix-str name)))
	(Inheritance
		pau
		(Concept "PAU"))
	(psi-set-value! pau initial-value)
	;(hash-set! prev-value-table pau initial-value)
	pau)

; arousal ultradian rhythm rule
(define arousal_B .05)
(define arousal_B .05)
(define arousal_w .02)
(define arousal_offset (get-random-cycle-offset arousal_w))
(define arousal_noise .03)

; arousal rhythm rule
(psi-create-general-rule (TrueLink)
	(GroundedSchemaNode "scm: psi-ultradian-update")
	(List arousal (Number arousal_B) (Number arousal_w) (Number arousal_offset)))

; arousal (stochastic) noise rule
(psi-create-general-rule (TrueLink)
	(GroundedSchemaNode "scm: psi-noise-update" arousal arousal_noise)
	(List arousal (Number arousal_noise)))

; ------------------------------------------------------------------
; OpenPsi Dynamics Interaction Rules
; The following change-predicate types have been defined in
; opencog/opencog/openpsi/interaction-rule.scm:
;(define changed "changed")
;(define increased "increased")
;(define decreased "decreased")

;--------------------------------
; Internal dynamic interactions

; power increases arousal
;(define power->arousal
;	(psi-create-interaction-rule power changed arousal .3))

; arousal decreases resolution
(psi-create-interaction-rule arousal changed resolution-level .5)

; arousal increases goal directedness
(psi-create-interaction-rule arousal changed goal-directedness .5)

; power decreases neg valence
(psi-create-interaction-rule power changed neg-valence -.2)

; arousal increases pos valence
(psi-create-interaction-rule arousal changed pos-valence .2)

; pos valence increases power
(psi-create-interaction-rule pos-valence changed power .2)


;-----------------------
; Event-based triggers

; User dialog sentiment
(define pos-sentiment->pos-valence
	(psi-create-interaction-rule positive-sentiment-dialog
		increased pos-valence .3))
(define pos-sentiment->neg-valence
	(psi-create-interaction-rule positive-sentiment-dialog
		increased neg-valence -.3))
(define neg-sentiment->neg-valence
	(psi-create-interaction-rule negative-sentiment-dialog
		increased neg-valence .3))
(define neg-sentiment->pos-valence
	(psi-create-interaction-rule negative-sentiment-dialog
		increased pos-valence -.3))

; Speech giving starts
(define speech->power
	(psi-create-interaction-rule speech-giving-starts increased
		power .5))

; Loud noise occurs
(define loud-noise (DefinedPredicate "Heard Loud Voice?"))
(psi-create-interaction-rule loud-noise increased arousal .9)
(psi-create-interaction-rule loud-noise increased neg-valence .7)

; Loud noise - previous approach that uses event callback approach
;(define loud-noise->arousal (psi-create-interaction-rule loud-noise-event
;	increased arousal 1))
;(define loud-noise->neg-valence (psi-create-interaction-rule loud-noise-event
;	increased neg-valence .7))

; New face
(define new-face->arousal
	(psi-create-interaction-rule new-face increased arousal .3))

; Voice width
(define voice-width
	(create-pau "voice width" .2))

; power increases voice-width
(define power->voice
	(psi-create-interaction-rule power changed voice-width .7))

; arousal decreases voice-width
(define arousal->voice
	(psi-create-interaction-rule arousal changed voice-width -.3))


; --------------------------------------------------------------
; Psi Emotion Representations
; Todo: move to psi-emotions.scm file?

(define psi-emotion-node (Concept (string-append psi-prefix-str "emotion")))

(define (psi-create-emotion emotion)
	(define emotion-concept (Concept (string-append psi-prefix-str emotion)))
	(Inheritance emotion-concept psi-emotion-node)
	; initialize value ?
	(psi-set-value! emotion-concept 0)
	;(format #t "new emotion: ~a\n" emotion-concept)
	emotion-concept)

(define-public (psi-get-emotion)
"
  Returns a list of all psi emotions.
"
	(filter
		(lambda (x) (not (equal? x psi-emotion-node)))
		(cog-chase-link 'InheritanceLink 'ConceptNode psi-emotion-node))
)

; Create emotions
(define psi-happy (psi-create-emotion "happy"))
(define psi-sad (psi-create-emotion "sad"))
(define psi-excited (psi-create-emotion "excited"))
(define psi-tired (psi-create-emotion "tired"))

; ------------------------------------------------------------------
; Run the dyanmics updater loop. Eventually this will be part of the main
; OpenPsi loop.
(psi-updater-run)


; ------------------------------------------------------------------
; Shortcuts for dev and testing purposes
; --------------------------------------------------------------
(define e psi-set-event-occurrence!)

(define halt psi-updater-halt)
(define h halt)
(define r psi-updater-run)
;(define r1 speech->power)
;(define r2 power->voice)
(define value psi-get-number-value)
(define rules psi-get-interaction-rules)

(define (psi-decrease-value target)
	(psi-set-value! target
		(max 0 (- (psi-get-number-value target) .1))))
(define (psi-increase-value target)
	(psi-set-value! target
		(min 1 (+ (psi-get-number-value target) .1))))

(define d psi-decrease-value)
(define i psi-increase-value)

(define (psi-set-pred-true target)
	(Evaluation target (List) (stv 1 1)))
(define (psi-set-pred-false target)
	(Evaluation target (List) (stv 0 1)))

(define t psi-set-pred-true)
(define f psi-set-pred-false)

(define nv neg-valence)
(define pv pos-valence)

(define (place-neg-dialog)
	(define sentence (SentenceNode (number->string (random 1000000000))))
	(State (Anchor "Chatbot: InputUtteranceSentence")  sentence)
	(Inheritance sentence (Concept "Negative")))

(define (place-pos-dialog)
	(define sentence (SentenceNode (number->string (random 1000000000))))
	(State (Anchor "Chatbot: InputUtteranceSentence")  sentence)
	(Inheritance sentence (Concept "Positive")))

(define (simulate-loud-noise)
	(define sudden-sound-change (AnchorNode "Sudden sound change value"))
	(call-with-new-thread
		(lambda ()
			(psi-set-value! sudden-sound-change 1)
			(sleep 2)
			(psi-set-value! sudden-sound-change 0))))

; Shortcuts
(define-public v voice-width)
(define-public p power)
(define-public a arousal)

(define-public n simulate-loud-noise)
(define-public ln simulate-loud-noise)

(define-public nd place-neg-dialog)   ; nd neg dialog
(define-public pd place-pos-dialog)   ; pd pos dialog

(define s speech-giving-starts)
(define pos positive-sentiment-dialog)
(define neg negative-sentiment-dialog)
(define nf new-face)








