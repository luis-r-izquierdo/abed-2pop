;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; GNU GENERAL PUBLIC LICENSE ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ABED-2pop
;; ABED-2pop (Agent-Based Evolutionary Dynamics in 2 populations)
;; is a modeling framework designed to simulate the evolution of two
;; populations of agents who play a 2-player game. Agents in one population
;; play the game against agents in the other population. Every agent is
;; occasionally given the opportunity to revise his strategy.
;; Copyright (C) 2017 Luis R. Izquierdo, Segismundo S. Izquierdo & Bill Sandholm
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;; Contact information:
;; Luis R. Izquierdo
;;   University of Burgos, Spain.
;;   e-mail: lrizquierdo@ubu.es

extensions [rnd]
;; for rnd:weighted-one-of, for clarity of code
;; (this can be done equally efficiently using rd-index-by-weights-from)


;;;;;;;;;;;;;;;;;
;;; Variables ;;;
;;;;;;;;;;;;;;;;;

globals [
  pop-1-agents
  pop-2-agents

  pop-1-payoff-matrix
  pop-2-payoff-matrix

  pop-1-n-of-strategies
  pop-2-n-of-strategies

  pop-1-strategies-payoffs
  pop-2-strategies-payoffs

  ;; plotting
  ticks-per-second
  plotting-period
  second-to-plot

  ;; tasks
  follow-rule
  update-payoff
  update-candidates-and-payoffs
  update-candidate-agents
  update-counterparts
  reported-counterparts
  tie-winner-in

  ;; for pairwise-difference, linear-dissatisfaction and linear-attraction
  pop-1-max-payoff-difference   ;; for efficiency
  pop-2-max-payoff-difference   ;; for efficiency

  ;; for linear-dissatisfaction
  pop-1-max-payoff   ;; for efficiency
  pop-2-max-payoff   ;; for efficiency

  ;; for linear attraction
  pop-1-min-payoff   ;; for efficiency
  pop-2-min-payoff   ;; for efficiency

  pop-1-max-n-of-candidates ;; for both direct and imitative protocols
  pop-2-max-n-of-candidates ;; for both direct and imitative protocols

  pop-1-strategy-numbers ;; for efficiency
  pop-2-strategy-numbers ;; for efficiency

  list-of-parameters ;; to save and load parameters

  ;; for random-walk tie-breaker
  random-walk-speed
  pop-1-rw-st-freq-non-committed-agents
  pop-2-rw-st-freq-non-committed-agents
]


breed [players player]
breed [strategy-agents strategy-agent]

players-own [
  strategy      ;; an integer >= 1
  next-strategy ;; to model synchronous revision
  payoff

  my-pop       ;; agentset with all the agents in my population (includig myself)
  my-pop-number
               ;; this is either 1 or 2

  the-other-pop-list
               ;; list with all the agents in the other population.
               ;; We implement it as a list because this is useful to create the counterparts, and
               ;; counterparts must be a list (to allow for trials-with-replacement?).
               ;; Thus, by selecting directly form a list we avoid the step of turning an agentset into a list.

  other-agents-in-my-pop
               ;; this agentset is useful to create the set of potential imitatees
               ;; if not consider-imitating-self?

  counterparts ;; list with the agents to play with.
               ;; counterparts is a list rather than a set so we can deal with replacement.
               ;; Lists can contain duplicates, but agentsets cannot.

  candidates   ;; list (or agentset) containing the group of entities you are going to select from.
               ;; Entities are agents if candidate-selection = imitative, and
               ;; in that case candidates is a list of agents (so we can deal with replacement,
               ;; since lists can contain duplicates, but agentsets cannot.)
               ;; Entities are strategies if candidate-selection = direct, and
               ;; in that case candidates is an agentset of strategy-agents.

  potential-imitatees
               ;; the set of potential imitatees;
               ;; equal to either my-pop or other-agents-in-my-pop

  played?      ;; true if the agent has played in this tick, false otherwise
]

strategy-agents-own [
  strategy     ;; an integer >= 1
  my-pop-number
               ;; this is either 1 or 2
  payoff
  counterparts ;; list with the agents to play with.
               ;; counterparts is a list rather than a set so we can deal with replacement.
               ;; Lists can contain duplicates, but agentsets cannot.
]

;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;

to startup
  clear-all
  no-display

  setup-payoffs

  carefully [
    setup-agents
    setup-strategy-agents

    setup-dynamics

    if decision-method = "pairwise-difference"
       or decision-method = "linear-dissatisfaction"
       or decision-method = "linear-attraction"
       [
         set pop-1-n-of-candidates 2
         set pop-2-n-of-candidates 2
       ]
    ;; the lines above are included here, rather than in setup-dynamics, because,
    ;; at runtime, this code is best executed within each decision-method,
    ;; just before pop-X-n-to-consider is used, to avoid any runtime errors.

    update-ticks-per-second
    update-strategies-payoffs

    reset-ticks
    setup-graphs

    setup-list-of-parameters
  ]
  [print error-message]

end

to setup-agents

  ifelse random-initial-condition?
  [
    create-players pop-1-n-of-agents [
      set strategy 1 + random pop-1-n-of-strategies
      set my-pop-number 1

    ]
    create-players pop-2-n-of-agents [
      set strategy 1 + random pop-2-n-of-strategies
      set my-pop-number 2
    ]
    ask players [
      set payoff 0
      set next-strategy strategy ;; to make sure that if you do not change next-strategy, you keep the same strategy
      set hidden? true
    ]
  ]
  [
    setup-population pop-1-n-of-agents-for-each-strategy 1
    setup-population pop-2-n-of-agents-for-each-strategy 2
  ]

  reset-populations
end


to setup-population [n-of-agents-for-each-strategy pop]
  let initial-distribution read-from-string n-of-agents-for-each-strategy

  let i 0
  foreach initial-distribution [
    [x] ->
    create-players x [
      set payoff 0
      set strategy (i + 1)
      set my-pop-number pop
      set next-strategy strategy ;; to make sure that if you do not change next-strategy, you keep the same strategy
      set hidden? true
    ]
    set i (i + 1)
  ]
end

to reset-populations

  set pop-1-agents players with [my-pop-number = 1]
  set pop-2-agents players with [my-pop-number = 2]

  set pop-1-n-of-agents (count pop-1-agents)
  set pop-2-n-of-agents (count pop-2-agents)

  ask pop-1-agents [
    set my-pop pop-1-agents
    set other-agents-in-my-pop other pop-1-agents
    set the-other-pop-list sort pop-2-agents
  ]
  ask pop-2-agents [
    set my-pop pop-2-agents
    set other-agents-in-my-pop other pop-2-agents
    set the-other-pop-list sort pop-1-agents
  ]

  set n-of-revisions-per-tick min (list n-of-revisions-per-tick (pop-1-n-of-agents + pop-2-n-of-agents))
  set random-walk-speed 1
  pop-1-setup-random-walk
  pop-2-setup-random-walk

end

to setup-strategy-agents
  let i 1
  create-strategy-agents pop-1-n-of-strategies [
    set my-pop-number 1
    set strategy i
    set i (i + 1)
  ]
  set i 1
  create-strategy-agents pop-2-n-of-strategies [
    set my-pop-number 2
    set strategy i
    set i (i + 1)
  ]
  ask strategy-agents [
    set payoff 0
    set hidden? true
  ]
end

to setup-dynamics
  ;; CHECK PAYOFFS
  if decision-method = "positive-proportional" [ check-all-payoffs-are-non-negative ]

  ;; SELECT YOUR NEXT STRATEGY DIRECTLY, OR VIA IMITATION
  ifelse (candidate-selection = "direct")
    [ set update-candidates-and-payoffs [ [] -> update-candidate-strategies-and-payoffs ] ]
    [ set update-candidates-and-payoffs [ [] -> update-candidate-agents-and-payoffs ] ]

  ;; NUMBER OF CANDIDATES REVISING AGENTS WILL CONSIDER
  ifelse (candidate-selection = "direct")
    [ ;; in direct protocols, candidates are strategies
      set pop-1-max-n-of-candidates pop-1-n-of-strategies
      set pop-2-max-n-of-candidates pop-2-n-of-strategies
    ]
    [ ;; in imitative protocols, candidates are agents
      let correction-factor ifelse-value consider-imitating-self? [1][0]
      set pop-1-max-n-of-candidates (pop-1-n-of-agents + correction-factor)
      set pop-2-max-n-of-candidates (pop-2-n-of-agents + correction-factor)
        ;; remember that the revising agent is always part of the set of candidates
    ]
  set pop-1-n-of-candidates min list pop-1-n-of-candidates pop-1-max-n-of-candidates
  set pop-2-n-of-candidates min list pop-2-n-of-candidates pop-2-max-n-of-candidates

  ;; RULE USED TO SELECT AMONG DIFFERENT CANDIDATES
  set follow-rule runresult (word "[ [] -> " decision-method " ]")

  ;; TIE-BREAKER
  set tie-winner-in runresult (word "[ [x] -> " tie-breaker " x ]")

  if not trials-with-replacement? [
    set n-of-trials min (list n-of-trials pop-1-n-of-agents pop-2-n-of-agents)
  ]

  ;; DO YOU PLAY EVERYONE?
  ifelse complete-matching?
    [
      set update-payoff [ [] -> update-payoff-full-matching ]
      set n-of-trials min list pop-1-n-of-agents pop-2-n-of-agents
      set trials-with-replacement? false
      set single-sample? true
    ]
    [ set update-payoff [ [] -> update-payoff-not-full-matching ] ]

  ;; DO YOU DRAW A DIFFERENT SAMPLE OF AGENTS TO PLAY WITH EVERY TIME YOU TEST A STRATEGY,
  ;; OR JUST ONE SINGLE SAMPLE FOR ALL YOUR TESTS? (ONLY RELEVANT IN DIRECT PROTOCOLS)
  ifelse single-sample?
    [ set reported-counterparts [ [] -> fixed-counterparts ] ]
    [ set reported-counterparts [ [] -> variable-counterparts ] ]

  ;; DO YOU SELECT THE AGENTS YOU ARE GOING TO PLAY WITH REPLACEMENT OR WITHOUT REPLACEMENT?
  ifelse trials-with-replacement?
    [ set update-counterparts [ [] -> update-counterparts-with-replacement ] ]
    [ set update-counterparts [ [] -> update-counterparts-without-replacement ] ]

  ifelse imitatees-with-replacement?
    [ set update-candidate-agents [ [] -> update-candidate-agents-with-replacement ] ]
    [ set update-candidate-agents [ [] -> update-candidate-agents-without-replacement ] ]

  ifelse consider-imitating-self?
    [ ask players [ set potential-imitatees my-pop] ]
    [ ask players [ set potential-imitatees other-agents-in-my-pop] ]

end

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Run-time procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go

  ;; the following two lines can be commented out if parameter values are not
  ;; going to change over the course of the simulation
  setup-dynamics
  update-ticks-per-second

  update-strategies-payoffs

  ask players [set played? false]
  ifelse use-prob-revision?
    [ask players with [random-float 1 < prob-revision] [update-strategy]]
    [ask n-of n-of-revisions-per-tick players [update-strategy]]

  tick
  ask players [set strategy next-strategy]

  ;; the following line can be commented out if the user does not
  ;; need the plots (e.g. if the model is run from BehaviorSpace)
  if (ticks mod (ceiling plotting-period) = 0) [update-graphs]

  ;; the following line can be commented out if the number of agents
  ;; is not going to be changed at runtime
  update-num-agents

  if (decision-method = "best" and tie-breaker = "random-walk") [
    if floor (ticks * random-walk-speed) > floor ((ticks - 1) * random-walk-speed)
      [pop-1-advance-random-walk pop-2-advance-random-walk]
  ]

end

to update-ticks-per-second
  ;; it is assumed that, on average, all agents revise once per second.
  set ticks-per-second ifelse-value use-prob-revision?
    [ 1 / prob-revision]
    [ (pop-1-n-of-agents + pop-2-n-of-agents) / n-of-revisions-per-tick ]

  if plot-every-?-secs < 1 / ticks-per-second [set plot-every-?-secs 1 / ticks-per-second]
  set plotting-period (ticks-per-second * plot-every-?-secs)
end

to update-num-agents
  let pop-1-diff (pop-1-n-of-agents - count pop-1-agents)
  let pop-2-diff (pop-2-n-of-agents - count pop-2-agents)

  if pop-1-diff != 0 or pop-2-diff != 0 [

    if pop-1-diff != 0 [
      ifelse pop-1-diff > 0
      [ repeat pop-1-diff [ ask one-of pop-1-agents [hatch-players 1] ] ]
      [ ask n-of (- pop-1-diff) pop-1-agents [die] ]
      pop-1-setup-random-walk ;; since the number of agents has changed
    ]

    if pop-2-diff != 0 [
      ifelse pop-2-diff > 0
      [ repeat pop-2-diff [ ask one-of pop-2-agents [hatch-players 1] ] ]
      [ ask n-of (- pop-2-diff) pop-2-agents [die] ]
      pop-2-setup-random-walk ;; since the number of agents has changed
    ]

    if not trials-with-replacement? [
      set n-of-trials min (list n-of-trials pop-1-n-of-agents pop-2-n-of-agents)
    ]

    reset-populations
  ]

end


;;;;;;;;;;;;;;;
;;; PAYOFFS ;;;
;;;;;;;;;;;;;;;

to setup-payoffs
  let payoffs read-from-string payoff-matrix

  carefully [

    set pop-1-payoff-matrix map [[row] -> map first row] payoffs
    set pop-2-payoff-matrix transpose-of map [[row] -> map last row] payoffs

    do-payoff-checks pop-1-payoff-matrix pop-1-n-of-agents-for-each-strategy
    do-payoff-checks pop-2-payoff-matrix pop-2-n-of-agents-for-each-strategy

    set pop-1-n-of-strategies length pop-1-payoff-matrix
    set pop-2-n-of-strategies length pop-2-payoff-matrix

    if decision-method = "positive-proportional" [ check-all-payoffs-are-non-negative ]

    set pop-1-strategy-numbers (range 1 (pop-1-n-of-strategies + 1))
    set pop-2-strategy-numbers (range 1 (pop-2-n-of-strategies + 1))

    set pop-1-max-payoff max-of-matrix pop-1-payoff-matrix
    set pop-2-max-payoff max-of-matrix pop-2-payoff-matrix

    set pop-1-min-payoff min-of-matrix pop-1-payoff-matrix
    set pop-2-min-payoff min-of-matrix pop-2-payoff-matrix

    set pop-1-max-payoff-difference pop-1-max-payoff - pop-1-min-payoff
    set pop-2-max-payoff-difference pop-2-max-payoff - pop-2-min-payoff

  ] [print error-message]
end


to do-payoff-checks [ matrix n-of-agents-for-each-strategy ]
  let initial-distribution read-from-string n-of-agents-for-each-strategy

  if length matrix != length initial-distribution [
    user-message (word "The number of items in n-of-agents-for-each-strategy (i.e. " length initial-distribution "):\n"
      initial-distribution "\nshould be equal to the number of rows of the payoff matrix (i.e. " length matrix "):\n"
      matrix
      )
  ]

  if length filter [ [x] -> x < 0] initial-distribution > 0 [
    user-message (word "All numbers in " initial-distribution "\nshould be non-negative numbers")
  ]
end

to check-all-payoffs-are-non-negative
  let any-changes? false

  if min reduce sentence pop-1-payoff-matrix < 0 [
    user-message (word
      "Since you are using decision-method = positive-proportional, all elements in the payoff matrix\n"
      put-sublists-in-different-lines-simple (word pop-1-payoff-matrix)
      "\nfor population 1 should be non-negative numbers.")
    if user-yes-or-no? (word
        "Would you like to add the minimum value to all elements in the payoff matrix for population 1?\n"
        put-sublists-in-different-lines-simple (word pop-1-payoff-matrix))
      [
        set pop-1-payoff-matrix make-elements-positive pop-1-payoff-matrix
        set any-changes? true
      ]
  ]

  if min reduce sentence pop-2-payoff-matrix < 0 [
    user-message (word
      "Since you are using decision-method = positive-proportional, all elements in the payoff matrix\n"
      put-sublists-in-different-lines-simple (word pop-2-payoff-matrix)
      "\nfor the population 2 should be non-negative numbers.")
    if user-yes-or-no? (word
        "Would you like to add the minimum value to all elements in the payoff matrix for population 2?\n"
        put-sublists-in-different-lines-simple (word pop-2-payoff-matrix))
      [
        set pop-2-payoff-matrix make-elements-positive pop-2-payoff-matrix
        set any-changes? true
      ]
  ]

  if any-changes? [
    set payoff-matrix put-sublists-in-different-lines (word (map [[l1 l2] -> (map list l1 l2)] pop-1-payoff-matrix (transpose-of pop-2-payoff-matrix)))
  ]

end

to-report make-elements-positive [m]
  let minimum min reduce sentence m
  report ifelse-value (minimum < 0)
    [ add-?-to-all-elements-of ( - minimum) m ]
    [ m ]
end

to update-strategies-payoffs
  ;; Population 1
  let pop-2-strategy-counts map [ [s] -> count pop-2-agents with [strategy = s]] pop-2-strategy-numbers
    ;; if nobody is playing a strategy, there's no problem in this model
  set pop-1-strategies-payoffs map [ [s] -> sum (map * pop-2-strategy-counts (item (s - 1) pop-1-payoff-matrix)) / pop-2-n-of-agents ] pop-1-strategy-numbers

  ;; Population 2
  let pop-1-strategy-counts map [ [s] -> count pop-1-agents with [strategy = s]] pop-1-strategy-numbers
    ;; if nobody is playing a strategy, there's no problem in this model
  set pop-2-strategies-payoffs map [ [s] -> sum (map * pop-1-strategy-counts (item (s - 1) pop-2-payoff-matrix)) / pop-1-n-of-agents ] pop-2-strategy-numbers
end

to have-payoff-ready
  if not played? [
    run update-payoff
    set played? true
  ]
end

to update-counterparts-with-replacement
  set counterparts n-values n-of-trials [one-of the-other-pop-list]
end

to update-counterparts-without-replacement
  set counterparts n-of n-of-trials the-other-pop-list
end

to update-payoff-full-matching
  set payoff item (strategy - 1) ifelse-value (my-pop-number = 1) [pop-1-strategies-payoffs][pop-2-strategies-payoffs]
end

to update-payoff-not-full-matching
  run update-counterparts
  let my-payoffs item (strategy - 1) ifelse-value (my-pop-number = 1) [pop-1-payoff-matrix][pop-2-payoff-matrix]
  let total-payoff sum (map * my-payoffs (strategy-freq counterparts (length my-payoffs)))
  set payoff total-payoff / n-of-trials
end

to-report strategy-freq [list-of-agents n-of-strategies]
  let str-freq n-values n-of-strategies [0]
  foreach list-of-agents [ [ag] ->
    let str ([strategy] of ag) - 1
    set str-freq replace-item str str-freq ((item str str-freq) + 1)
  ]
  report str-freq
end

;;;;;;;;;;;;;;;;;;;;;;;
;;; UPDATE-STRATEGY ;;;
;;;;;;;;;;;;;;;;;;;;;;;

to update-strategy
  ifelse random-float 1 < prob-mutation
  [set next-strategy (1 + random (ifelse-value (my-pop-number = 1) [pop-1-n-of-strategies][pop-2-n-of-strategies]))]
  [run follow-rule]
end

to update-candidate-agents-and-payoffs
  run update-candidate-agents
   ;; note that candidates is a list to select from, and you are always added to it.
   ;; candidates could have duplicates if imitatees-with-replacement? is on.
  ask (turtle-set candidates) [have-payoff-ready]
end

to update-candidate-agents-with-replacement
  set candidates (fput self (n-values (ifelse-value (my-pop-number = 1) [pop-1-n-of-candidates - 1][pop-2-n-of-candidates - 1]) [one-of potential-imitatees]))
end

to update-candidate-agents-without-replacement
  set candidates (fput self sort (n-of (ifelse-value (my-pop-number = 1) [pop-1-n-of-candidates - 1][pop-2-n-of-candidates - 1]) potential-imitatees))
end

to update-candidate-strategies-and-payoffs
  let my-strategy-agent one-of (strategy-agents with [strategy = [strategy] of myself and my-pop-number = [my-pop-number] of myself])
  set candidates (turtle-set
    my-strategy-agent
    n-of ((ifelse-value (my-pop-number = 1) [pop-1-n-of-candidates][pop-2-n-of-candidates]) - 1)
     (strategy-agents with [strategy != [strategy] of myself and my-pop-number = [my-pop-number] of myself])
  )
  ;; here candidates is an agentset (which contains strategy-agents)

  update-payoffs-of-strategy-agents candidates
  set payoff [payoff] of my-strategy-agent

end

to update-payoffs-of-strategy-agents [strategy-set]

  ifelse complete-matching?
  [
    ;; we have executed "update-strategies-payoffs" in "go" just before initiating revisions, so we're good.
    let strategies-payoffs (ifelse-value (my-pop-number = 1) [pop-1-strategies-payoffs][pop-2-strategies-payoffs])
    ask strategy-set [ set payoff item (strategy - 1) strategies-payoffs  ]
  ]
  [
    run update-counterparts

    ask strategy-set [
      set counterparts runresult reported-counterparts
        ;; reported-counterparts can be fixed-counterparts (if single-sample?)
        ;; or variable-counterparts (if not single-sample?)

      let my-payoffs item (strategy - 1) ifelse-value (my-pop-number = 1) [pop-1-payoff-matrix][pop-2-payoff-matrix]

      let total-payoff sum (map * my-payoffs (strategy-freq counterparts (length my-payoffs)))
      set payoff total-payoff / n-of-trials
    ]
  ]

end

;; POSSIBLE VALUES OF reported-counterparts

to-report fixed-counterparts
  report [counterparts] of myself
end

to-report variable-counterparts
  ask myself [run update-counterparts]
  report [counterparts] of myself
end

;; DECISION-METHODS

to best
  run update-candidates-and-payoffs
  let best-candidates items-with-max-payoff-in sort candidates
   ;; candidates here may be a list of agents (if candidate-selection = imitative), or
   ;; an agentset of strategy-agents (if candidate-selection = direct).
   ;; We cannot write ((turtle-set candidates) with-max [payoff]) because agentsets cannot contain duplicates,
   ;; and this is a problem if imitatees-with-replacement? is on.
  set next-strategy (runresult tie-winner-in map [ [c] -> [strategy] of c] best-candidates)
end

to pairwise-difference
  ;; useful relevant notes in Sandholm (2010, "Population Games and Evolutionary Dynamics", section 4.3.1, pp. 126-127)

  let max-payoff-difference (ifelse-value (my-pop-number = 1) [pop-1-max-payoff-difference][pop-2-max-payoff-difference])
  if max-payoff-difference != 0 [
    ;; max-payoff-difference is zero only if all elements in the payoff matrix are the same.
    ;; In that case there is nothing to do here.

    set pop-1-n-of-candidates 2
    set pop-2-n-of-candidates 2
    run update-candidates-and-payoffs

    let sorted-candidates sort-on [payoff] (turtle-set candidates)
    let worse first sorted-candidates
    let better last sorted-candidates
    let payoff-diff ([payoff] of better - [payoff] of worse)

    if random-float 1 < (payoff-diff / max-payoff-difference) [
      set next-strategy [strategy] of better
    ]
    ;; If your strategy is the better, you are going to stick with it
    ;; If it's not, you switch with probability (payoff-diff / max-payoff-difference)
  ]
end

to logit
  run update-candidates-and-payoffs
  carefully [
    let target-candidate rnd:weighted-one-of-list (sort candidates) [ [c] -> exp (([payoff] of c) / (10 ^ log-noise-level))]
    ;; candidates here may be a list of agents (if candidate-selection = imitative), or
    ;; an agentset of strategy-agents (if candidate-selection = direct).
    set next-strategy [strategy] of target-candidate
  ]
  [
    user-message "Logit has computed a number that is too big for IEEE 754 floating-point computation\nPlease consider using a higher value for log-noise-level."
    print error-message
  ]
end

to positive-proportional
  run update-candidates-and-payoffs
  let target-candidate rnd:weighted-one-of-list (sort candidates) [ [c] -> [payoff] of c]
    ;; candidates here may be a list of agents (if candidate-selection = imitative), or
    ;; an agentset of strategy-agents (if candidate-selection = direct).
  set next-strategy [strategy] of target-candidate
end

to linear-dissatisfaction

  let max-payoff-difference (ifelse-value (my-pop-number = 1) [pop-1-max-payoff-difference][pop-2-max-payoff-difference])
  if max-payoff-difference != 0 [
    ;; max-payoff-difference is zero only if all elements in the payoff matrix are the same.
    ;; In that case there is nothing to do here.

    let max-payoff (ifelse-value (my-pop-number = 1) [pop-1-max-payoff][pop-2-max-payoff])

    set pop-1-n-of-candidates 2
    set pop-2-n-of-candidates 2
    run update-candidates-and-payoffs
      ;; here the revising agent's payoff is updated,
      ;; so we can use payoff safely.

    let my-strategy strategy
    let the-other one-of ((turtle-set candidates) with [strategy != my-strategy])

    if the-other != nobody [
      ;; if the other one has your strategy too, it's fine, since
      ;; you are not going to change your strategy anyway.
      if random-float 1 < ((max-payoff - payoff) / max-payoff-difference) [
        set next-strategy [strategy] of the-other
      ]
    ]
  ]
end

to linear-attraction

  let max-payoff-difference (ifelse-value (my-pop-number = 1) [pop-1-max-payoff-difference][pop-2-max-payoff-difference])
  if max-payoff-difference != 0 [
    ;; max-payoff-difference is zero only if all elements in the payoff matrix are the same.
    ;; In that case there is nothing to do here.

    let min-payoff (ifelse-value (my-pop-number = 1) [pop-1-min-payoff][pop-2-min-payoff])

    set pop-1-n-of-candidates 2
    set pop-2-n-of-candidates 2
    run update-candidates-and-payoffs

    let my-strategy strategy
    let the-other one-of ((turtle-set candidates) with [strategy != my-strategy])

    if the-other != nobody [
      ;; if the other one has your strategy too, it's fine, since
      ;; you are not going to change your strategy anyway.
      if random-float 1 < (([payoff] of the-other - min-payoff) / max-payoff-difference) [
        set next-strategy [strategy] of the-other
      ]
    ]
  ]
end

;; TIE-BREAKERS

to-report stick-uniform [st-list]
  report ifelse-value member? strategy st-list [strategy] [one-of st-list]
end

to-report stick-min [st-list]
  report ifelse-value member? strategy st-list [strategy] [min st-list]
end

to-report uniform [st-list]
  report one-of st-list
end

to-report random-walk [st-list]
    ;; useful relevant notes in Sandholm (2010, "Population Games and Evolutionary Dynamics", section 11.4.3, pp. 421-423)
  report rnd:weighted-one-of-list st-list
    [ [s] -> 1 + item (s - 1) (ifelse-value (my-pop-number = 1) [pop-1-rw-st-freq-non-committed-agents][pop-2-rw-st-freq-non-committed-agents]) ]
    ;; We add one to the weights to account for the non-committed agents
end

to pop-1-setup-random-walk
  set pop-1-rw-st-freq-non-committed-agents tally-strategies (n-values pop-1-n-of-agents [1 + random pop-1-n-of-strategies]) pop-1-n-of-strategies
    ;; this list is pop-1-n-of-strategies long and, initially, it is a random distribution
end

to pop-2-setup-random-walk
  set pop-2-rw-st-freq-non-committed-agents tally-strategies (n-values pop-2-n-of-agents [1 + random pop-2-n-of-strategies]) pop-2-n-of-strategies
    ;; this list is pop-2-n-of-strategies long and, initially, it is a random distribution
end

to pop-1-advance-random-walk
  set pop-1-rw-st-freq-non-committed-agents (next-in-random-walk pop-1-rw-st-freq-non-committed-agents pop-1-strategy-numbers)
end

to pop-2-advance-random-walk
  set pop-2-rw-st-freq-non-committed-agents (next-in-random-walk pop-2-rw-st-freq-non-committed-agents pop-2-strategy-numbers)
end

to-report next-in-random-walk [rw-st-freq-non-committed-agents strategy-numbers]
  let imitator-st rnd:weighted-one-of-list strategy-numbers [ [s] -> item (s - 1) rw-st-freq-non-committed-agents]
    ;; imitator-st is intended to represent the strategy of
    ;; the agent who has been chosen to revise his strategy.
  let rw-st-freq-imitatees subtract-one-in-pos-?1-of-list-?2 (imitator-st - 1) rw-st-freq-non-committed-agents
    ;; rw-st-freq-imitatees is the strategy distribution
    ;; of the non-committed agents who may be chosen to be imitated
  let new-strategy rnd:weighted-one-of-list strategy-numbers [ [s] -> 1 + item (s - 1) rw-st-freq-imitatees]
    ;; We add one to the weights to account for the non-committed agents
  report add-one-in-pos-?1-of-list-?2 (new-strategy - 1) rw-st-freq-imitatees
end


;;;;;;;;;;;;;;
;;; GRAPHS ;;;
;;;;;;;;;;;;;;

to setup-graphs
  foreach [1 2] [[pop] ->
    setup-miliseconds-graph (word "Pop. " pop ": Strategy distributions (recent history)") 1 pop
    setup-graph (word "Pop. " pop ": Strategy distributions (complete history)") 1 pop

    setup-miliseconds-graph (word "Pop. " pop ": Strategies' exp. payoffs (recent history)") 0 pop
    setup-graph (word "Pop. " pop ": Strategies' exp. payoffs (complete history)") 0 pop
  ]
  update-graphs
end

to setup-graph [s mode pop]
  set-current-plot s
  foreach (ifelse-value (pop = 1) [pop-1-strategy-numbers][pop-2-strategy-numbers]) [ [n] ->
    create-temporary-plot-pen (word n)
    set-plot-pen-mode mode
    set-plot-pen-interval plot-every-?-secs
    set-plot-pen-color 25 + 40 * (n - 1)
  ]
end

to setup-miliseconds-graph [s mode pop]
  set-current-plot s
  foreach (ifelse-value (pop = 1) [pop-1-strategy-numbers][pop-2-strategy-numbers]) [ [n] ->
    create-temporary-plot-pen (word n)
    set-plot-pen-mode mode
    set-plot-pen-interval 1000 * plot-every-?-secs
    set-plot-pen-color 25 + 40 * (n - 1)
  ]
end

to update-graphs
  ;; Population 1
  let pop-2-strategy-frequencies map [ [s] -> count pop-2-agents with [strategy = s] / pop-2-n-of-agents] pop-2-strategy-numbers
  let pop-1-strategies-expected-payoff map [ [s] -> sum (map * pop-2-strategy-frequencies (item (s - 1) pop-1-payoff-matrix)) ] pop-1-strategy-numbers

  ;; Population 2
  let pop-1-strategy-frequencies map [ [s] -> count pop-1-agents with [strategy = s] / pop-1-n-of-agents] pop-1-strategy-numbers
  let pop-2-strategies-expected-payoff map [ [s] -> sum (map * pop-1-strategy-frequencies (item (s - 1) pop-2-payoff-matrix)) ] pop-2-strategy-numbers

  (foreach [1 2]
           (list pop-1-strategy-numbers pop-2-strategy-numbers)
           (list pop-1-strategy-frequencies pop-2-strategy-frequencies)
           (list pop-1-strategies-expected-payoff pop-2-strategies-expected-payoff)
  [ [pop strategy-numbers strategy-frequencies strategies-expected-payoff] ->
    if show-recent-history? [
      set-current-plot (word "Pop. " pop ": Strategy distributions (recent history)")
        plot-frequencies-?-at-? strategy-frequencies (1000 * second-to-plot) strategy-numbers
        fix-x-range

      set-current-plot (word "Pop. " pop ": Strategies' exp. payoffs (recent history)")
        foreach strategy-numbers [ [s] ->
          set-current-plot-pen (word s)
          ;; set-plot-pen-interval plot-every-?-ticks
          plotxy (1000 * second-to-plot) item (s - 1) strategies-expected-payoff
        ]
        fix-x-range
    ]

    if show-complete-history? [
      set-current-plot (word "Pop. " pop ": Strategy distributions (complete history)")
        plot-frequencies-?-at-? strategy-frequencies second-to-plot strategy-numbers

      set-current-plot (word "Pop. " pop ": Strategies' exp. payoffs (complete history)")
        foreach strategy-numbers [ [s] ->
          set-current-plot-pen (word s)
          ;; set-plot-pen-interval plot-every-?-ticks
          plotxy second-to-plot item (s - 1) strategies-expected-payoff
        ]
    ]
  ])
  set second-to-plot (second-to-plot + plot-every-?-secs)
end

to fix-x-range
  set-plot-x-range floor (max (list 0 (1000 * (second-to-plot - duration-of-recent)))) floor (1000 * second-to-plot + (1000 * plot-every-?-secs))
end

to plot-frequencies-?-at-? [freq x strategy-numbers]
  let bar 1
  foreach strategy-numbers [ [s] ->
    set-current-plot-pen (word s)
    ;; set-plot-pen-interval plot-every-?-secs
    plotxy x bar
    set bar (bar - (item (s - 1) freq))
  ]
  set-plot-y-range 0 1
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; SUPPORTING PROCEDURES ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;
;;; Matrices ;;;
;;;;;;;;;;;;;;;;

to-report max-of-matrix [m]
  report max reduce sentence m
end

to-report min-of-matrix [m]
  report min reduce sentence m
end

to-report transpose-of [m]
  let n-rows length m
  let n-cols length first m
  let mt n-values n-cols [n-values n-rows [0]]

  let r 0
  foreach m [ [m-row] ->
    let c 0
    foreach m-row [ [n] ->
      set mt replace-item c mt (replace-item r (item c mt) n)
      set c (c + 1)
    ]
    set r (r + 1)
  ]
  report mt
end

to-report add-?-to-all-elements-of [v m]
  report map [[row] -> map [[el] -> v + el] row] m
end

;;;;;;;;;;;;;
;;; Lists ;;;
;;;;;;;;;;;;;

to-report all-equal? [l]
  let first-element first l
  report reduce and (map [ [el] -> el = first-element] l)
end

to-report max-positions [numbers]
  let biggest max numbers
  report filter [ [n] -> item n numbers = biggest] (range (length numbers))
end

to-report items-with-max-payoff-in [l]
  let items []
  let max-payoff [payoff] of first l
  foreach l [ [el] ->
    let payoff-of-item [payoff] of el
    if payoff-of-item >= max-payoff [
      ifelse payoff-of-item = max-payoff
        [ set items lput el items ]
        [
          set max-payoff payoff-of-item
          set items (list el)
        ]
    ]
  ]
  report items
end

to-report tally [l]
  ;; it is assumed that the l is a list that contains natural numbers only
  let M max l
  let h n-values (M + 1) [0]
  foreach l [ [el] ->
    set h replace-item el h ((item el h) + 1)
    ]
  report h
end

to-report tally-strategies [l n-of-strategies]
  ;; it is assumed that the l is a list that contains strategy numbers only
  let h n-values n-of-strategies [0]
  foreach l [ [s] ->
    set h replace-item (s - 1) h ((item (s - 1) h) + 1)
    ]
  report h
end

to-report subtract-one-in-pos-?1-of-list-?2 [pos l]
  report replace-item pos l ((item pos l) - 1)
end

to-report add-one-in-pos-?1-of-list-?2 [pos l]
  report replace-item pos l ((item pos l) + 1)
end



;;;;;;;;;;;;;;;;;;;;;
;; Parameter files ;;
;;;;;;;;;;;;;;;;;;;;;

to setup-list-of-parameters
  set list-of-parameters (list
    "payoff-matrix"
    "pop-1-n-of-agents"
    "pop-2-n-of-agents"
    "random-initial-condition?"
    "pop-1-n-of-agents-for-each-strategy"
    "pop-2-n-of-agents-for-each-strategy"
    "use-prob-revision?"
    "prob-revision"
    "n-of-revisions-per-tick"
    "candidate-selection"
    "pop-1-n-of-candidates"
    "pop-2-n-of-candidates"
    "complete-matching?"
    "n-of-trials"
    "single-sample?"
    "decision-method"
    "prob-mutation"
    "tie-breaker"
    "log-noise-level"
    "trials-with-replacement?"
    "imitatees-with-replacement?"
    "consider-imitating-self?"
    "plot-every-?-secs"
    "duration-of-recent"
    "show-recent-history?"
    "show-complete-history?"
    )
end


;; This procedure loads in data from a text file and sets the variables accordingly.
to load-parameter-file
  let file user-file

  ;; Note that we need to check that file isn't false. user-file
  ;; will return false if the user cancels the file dialog.
  if ( file != false )
  [
    ;; This opens the file, so we can use it.
    file-open file

    ;; Read in the file (assumed to be in exactly the same format as when saved )
    while [not file-at-end?]
    [
      let string file-read-line
      let comma-position position "," string
      let variable-name substring string 0 comma-position
      let value substring string (comma-position + 1) (length string)
      run (word "set " variable-name " " value)
    ]

    set payoff-matrix put-sublists-in-different-lines payoff-matrix

    user-message "File loading complete!"

    ;; Done reading in the information.  Close the file.
    file-close

    startup
  ]

end

to-report put-sublists-in-different-lines [s]
  let open-bracket-pos position "[" s
  set s substring s (open-bracket-pos + 1) (length s)
  let close-bracket-pos -1

  let new-s "[\n "

  set open-bracket-pos position "[" s
  while [open-bracket-pos != false] [
    set close-bracket-pos position-of-second-closing-bracket s
    set new-s (word new-s (substring s open-bracket-pos (close-bracket-pos + 1)) "\n ")
    set s substring s (close-bracket-pos + 1) (length s)
    set open-bracket-pos position "[" s
  ]
  report (word substring new-s 0 (length new-s - 2) "\n]")

end

to-report position-of-second-closing-bracket [str]
  let running-str str
  let opening-bracket-pos position "[" running-str
  while [position "[" running-str != false and (position "[" running-str < position "]" running-str) ] [
    set running-str substring running-str (position "]" running-str + 1) (length running-str)
  ]
  let second-position position "]" running-str
  ifelse second-position = false [report false][
    report (length str - length running-str) + second-position
  ]
end

to-report put-sublists-in-different-lines-simple [s]
  let open-bracket-pos position "[" s
  set s substring s (open-bracket-pos + 1) (length s)
  let close-bracket-pos -1

  let new-s "["

  set open-bracket-pos position "[" s
  while [open-bracket-pos != false] [
    set close-bracket-pos position "]" s
    set new-s (word new-s (substring s open-bracket-pos (close-bracket-pos + 1)) "\n ")
    set s substring s (close-bracket-pos + 1) (length s)
    set open-bracket-pos position "[" s
  ]
  report (word substring new-s 0 (length new-s - 2) "]")
end

;; This procedure saves the parameters into a new file
;; or appends the data to an existing file
to save-parameter-file
  let file user-new-file

  if ( file != false )
  [
    carefully [file-delete file] [] ;; overwrite the file if it exists
    file-open file

    foreach list-of-parameters [ [p] -> file-print (word p "," (fix-string runresult p)) ]
    file-close
  ]
end

to-report fix-string [s]
  ;;report ifelse-value is-string? s [remove "\n" s][s]
  report ifelse-value is-string? s [ (word "\"" (remove "\n" s)  "\"") ] [s]
end

;;;;;;;;;;;;;;;;;;;;;;
;;; Random numbers ;;;
;;;;;;;;;;;;;;;;;;;;;;

;to-report cum-list-from [w]
;  let cum-list (list first w)
;  ;; cum-list first value is the first value of w, and it is as long as w
;  foreach but-first w [set cum-list lput (? + last cum-list) cum-list]
;  report cum-list
;end
;
;to-report rd-index-by-cumulative-weights [cw]
;  let rd-index 0
;  let tmp random-float last cw
;  ;; select the new strategy with probability proportional to the elements of i-d
;  foreach cw [ if (tmp > ?) [set rd-index (rd-index + 1)] ]
;  report rd-index
;end
;
;to-report rd-index-by-weights-from [w]
;  report rd-index-by-cumulative-weights (cum-list-from w)
;end

;; if speed is critical, consider using extension rnd (https://github.com/NetLogo/Rnd-Extension)
;; The extension uses Keith Schwarz's implementation of Vose's Alias Method (see http://www.keithschwarz.com/darts-dice-coins/).
;; Assuming you are choosing n candidates for a collection of size m with repeats, this method has an initialization cost of O(m),
;; followed by a cost of O(1) for each item you pick, so O(m + n) overall.
;; rnd:weighted-n-of-list-with-repeats implements

;; examples and speed comparisons in file random-sampling-weights.nlogo
@#$#@#$#@
GRAPHICS-WINDOW
524
78
557
102
-1
-1
5.0
1
10
1
1
1
0
0
0
1
-2
2
-1
1
0
0
1
ticks
30.0

INPUTBOX
25
347
251
494
payoff-matrix
[\n [[ 0 0][0 0][0 0][0 0][0  0][0 0]]\n [[-1 3][2 2][2 2][2 2][2  2][2 2]]\n [[-1 3][1 5][4 4][4 4][4  4][4 4]]\n [[-1 3][1 5][3 7][6 6][6  6][6 6]]\n [[-1 3][1 5][3 7][5 9][8  8][8 8]]\n [[-1 3][1 5][3 7][5 9][7 11][10 10]]\n]
1
1
String (reporter)

SLIDER
287
383
475
416
prob-revision
prob-revision
0.001
1
0.001
0.001
1
NIL
HORIZONTAL

SLIDER
547
633
704
666
prob-mutation
prob-mutation
0
1
0.001
0.001
1
NIL
HORIZONTAL

BUTTON
25
10
109
43
setup
startup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
221
10
301
43
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
120
10
209
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
677
10
797
55
NIL
ticks
17
1
11

PLOT
25
60
469
186
Pop. 1: Strategy distributions (recent history)
milliseconds
NIL
0.0
10.0
0.0
1.0
true
true
"" ""
PENS

PLOT
475
60
931
186
Pop. 1: Strategy distributions (complete history)
seconds
NIL
0.0
1.0
0.0
1.0
true
true
"" ""
PENS

SLIDER
284
558
479
591
duration-of-recent
duration-of-recent
1
100
20.0
1
1
sec.
HORIZONTAL

SWITCH
285
597
479
630
show-recent-history?
show-recent-history?
0
1
-1000

SWITCH
285
633
478
666
show-complete-history?
show-complete-history?
0
1
-1000

INPUTBOX
24
539
249
599
pop-1-n-of-agents-for-each-strategy
[500 0 0 0 0 0]
1
0
String (reporter)

SWITCH
287
346
475
379
use-prob-revision?
use-prob-revision?
1
1
-1000

SLIDER
284
518
479
551
plot-every-?-secs
plot-every-?-secs
0.01
5
0.05
0.01
1
NIL
HORIZONTAL

SLIDER
288
420
475
453
n-of-revisions-per-tick
n-of-revisions-per-tick
1
pop-1-n-of-agents + pop-2-n-of-agents
50.0
1
1
NIL
HORIZONTAL

MONITOR
808
10
929
55
NIL
ticks-per-second
3
1
11

SWITCH
748
346
930
379
complete-matching?
complete-matching?
1
1
-1000

SLIDER
747
399
930
432
n-of-trials
n-of-trials
1
10
1.0
1
1
NIL
HORIZONTAL

SLIDER
518
399
719
432
pop-1-n-of-candidates
pop-1-n-of-candidates
2
pop-1-max-n-of-candidates
6.0
1
1
NIL
HORIZONTAL

TEXTBOX
759
624
927
642
for decision-method = logit:
11
0.0
1

SLIDER
756
640
907
673
log-noise-level
log-noise-level
-3
3
0.0
0.001
1
NIL
HORIZONTAL

CHOOSER
756
577
908
622
tie-breaker
tie-breaker
"stick-uniform" "stick-min" "uniform" "min" "random-walk"
3

TEXTBOX
758
560
927
588
for decision-method = best:
11
0.0
1

TEXTBOX
520
472
722
533
Under imitative protocols, \n      candidates are agents.\nUnder direct protocols, \n      candidates are strategies.
11
0.0
1

CHOOSER
518
346
685
391
candidate-selection
candidate-selection
"imitative" "direct"
1

CHOOSER
530
564
705
609
decision-method
decision-method
"best" "logit" "positive-proportional" "pairwise-difference" "linear-dissatisfaction" "linear-attraction"
0

TEXTBOX
747
438
933
468
for complete-matching=off \n  & candidate-selection = direct:
11
0.0
1

SWITCH
773
472
930
505
single-sample?
single-sample?
1
1
-1000

SWITCH
25
931
231
964
trials-with-replacement?
trials-with-replacement?
0
1
-1000

SWITCH
25
857
242
890
imitatees-with-replacement?
imitatees-with-replacement?
1
1
-1000

SWITCH
25
821
242
854
consider-imitating-self?
consider-imitating-self?
1
1
-1000

PLOT
260
683
588
829
Pop. 1: Strategies' exp. payoffs (recent history)
milliseconds
NIL
0.0
1.0
0.0
0.0
true
true
"" ""
PENS

PLOT
590
683
927
829
Pop. 1: Strategies' exp. payoffs (complete history)
seconds
NIL
0.0
1.0
0.0
0.0
true
true
"" ""
PENS

BUTTON
329
10
489
43
load parameters from file
load-parameter-file
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
499
10
646
43
save parameters to file
save-parameter-file
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
25
804
246
832
for candidate-selection = imitative:\n
11
0.0
1

TEXTBOX
749
383
916
401
for complete-matching=off:
11
0.0
1

TEXTBOX
266
324
508
356
Assignment of revision opportunities
13
13.0
1

TEXTBOX
810
325
883
343
Matching
13
13.0
1

TEXTBOX
539
325
689
343
Candidate selection
13
13.0
1

TEXTBOX
547
617
697
635
mutations:
11
0.0
1

TEXTBOX
672
538
802
556
Decision method
13
13.0
1

TEXTBOX
60
324
210
342
Game and population
13
13.0
1

TEXTBOX
324
498
442
516
Plotting of output
12
0.0
1

TEXTBOX
27
914
216
932
for complete-matching = off:
11
0.0
1

TEXTBOX
26
750
245
768
---------------------------------------\n
11
0.0
1

INPUTBOX
24
603
249
663
pop-2-n-of-agents-for-each-strategy
[500 0 0 0 0 0]
1
0
String (reporter)

SLIDER
518
435
719
468
pop-2-n-of-candidates
pop-2-n-of-candidates
2
pop-2-max-n-of-candidates
6.0
1
1
NIL
HORIZONTAL

SLIDER
24
667
249
700
pop-1-n-of-agents
pop-1-n-of-agents
1
2000
500.0
1
1
NIL
HORIZONTAL

SLIDER
24
703
249
736
pop-2-n-of-agents
pop-2-n-of-agents
1
2000
500.0
1
1
NIL
HORIZONTAL

SWITCH
25
498
251
531
random-initial-condition?
random-initial-condition?
1
1
-1000

PLOT
25
187
469
317
Pop. 2: Strategy distributions (recent history)
milliseconds
NIL
0.0
10.0
0.0
1.0
true
true
"" ""
PENS

PLOT
475
187
931
317
Pop. 2: Strategy distributions (complete history)
seconds
NIL
0.0
1.0
0.0
1.0
true
true
"" ""
PENS

PLOT
260
831
588
977
Pop. 2: Strategies' exp. payoffs (recent history)
milliseconds
NIL
0.0
1.0
0.0
0.0
true
true
"" ""
PENS

PLOT
590
831
927
976
Pop. 2: Strategies' exp. payoffs (complete history)
seconds
NIL
0.0
1.0
0.0
0.0
true
true
"" ""
PENS

TEXTBOX
57
777
218
795
Auxiliary parameters
13
13.0
1

@#$#@#$#@
## HOW TO USE THIS MODEL

Please, find all the information about this model at
https://luis-r-izquierdo.github.io/abed-2pop/
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
