(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_VOTED (err u101))
(define-constant ERR_INVALID_PROPOSAL (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_VOTING_ACTIVE (err u104))
(define-constant ERR_INSUFFICIENT_STAKE (err u105))
(define-constant ERR_ALREADY_MEMBER (err u106))
(define-constant ERR_NOT_MEMBER (err u107))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u108))
(define-constant ERR_DISPUTE_NOT_FOUND (err u109))
(define-constant ERR_DISPUTE_CLOSED (err u110))
(define-constant ERR_INVALID_DISPUTE_STAGE (err u111))
(define-constant ERR_ARBITRATOR_NOT_QUALIFIED (err u112))
(define-constant ERR_INVALID_RESOLUTION_TYPE (err u113))
(define-constant ERR_MEDIATION_FAILED (err u114))
(define-constant ERR_APPEAL_WINDOW_CLOSED (err u115))
(define-constant ERR_INSUFFICIENT_ARBITRATOR_STAKE (err u116))
(define-constant ERR_ALREADY_ARBITRATOR (err u117))
(define-constant ERR_NOT_ARBITRATOR (err u118))
(define-constant ERR_DISPUTE_STAGE_MISMATCH (err u119))
(define-constant ERR_INVALID_MEDIATION_PROPOSAL (err u120))

(define-data-var next-proposal-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var arbitrator-min-stake uint u5000000)
(define-data-var mediation-period uint u720)
(define-data-var arbitration-period uint u1008)
(define-data-var appeal-window uint u504)
(define-data-var min-stake-amount uint u1000000)
(define-data-var voting-period uint u1440)
(define-data-var quorum-threshold uint u51)

(define-map dao-members principal 
  {
    stake-amount: uint,
    joined-at: uint,
    reputation: uint
  }
)

(define-map breach-proposals uint
  {
    proposer: principal,
    company-name: (string-ascii 100),
    breach-description: (string-ascii 500),
    evidence-hash: (string-ascii 64),
    severity-level: uint,
    created-at: uint,
    voting-ends-at: uint,
    yes-votes: uint,
    no-votes: uint,
    total-voters: uint,
    status: (string-ascii 20),
    reward-pool: uint
  }
)

(define-map proposal-votes {proposal-id: uint, voter: principal}
  {
    vote: bool,
    stake-weight: uint,
    voted-at: uint
  }
)

(define-map whistleblower-rewards principal uint)

(define-map arbitrators principal
  {
    stake-amount: uint,
    cases-handled: uint,
    reputation-score: uint,
    specialization: (string-ascii 50),
    joined-at: uint,
    status: (string-ascii 20)
  }
)

(define-map disputes uint
  {
    initiator: principal,
    respondent: principal,
    dispute-type: (string-ascii 50),
    description: (string-ascii 1000),
    evidence-hash: (string-ascii 64),
    stage: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    stake-amount: uint,
    assigned-arbitrator: (optional principal),
    mediation-proposal: (optional (string-ascii 500)),
    resolution: (optional (string-ascii 500)),
    appeal-count: uint,
    final-decision: (optional (string-ascii 500)),
    resolution-type: (string-ascii 20),
    mediation-deadline: uint,
    arbitration-deadline: uint,
    appeal-deadline: uint
  }
)

(define-map dispute-votes {dispute-id: uint, voter: principal}
  {
    resolution-support: bool,
    voted-at: uint,
    vote-weight: uint
  }
)

(define-map dispute-appeals uint
  {
    appellant: principal,
    appeal-reason: (string-ascii 500),
    appeal-evidence: (string-ascii 64),
    appeal-fee: uint,
    appeal-stage: (string-ascii 20),
    created-at: uint,
    panel-decision: (optional (string-ascii 500))
  }
)

(define-map mediation-sessions {dispute-id: uint, session-id: uint}
  {
    mediator: principal,
    session-type: (string-ascii 30),
    outcome: (string-ascii 20),
    agreements: (optional (string-ascii 500)),
    created-at: uint,
    completed-at: (optional uint)
  }
)

(define-map company-breach-history (string-ascii 100)
  {
    total-breaches: uint,
    severity-score: uint,
    last-breach: uint
  }
)

(define-public (join-dao)
  (let
    (
      (caller tx-sender)
      (stake-amount (var-get min-stake-amount))
    )
    (asserts! (is-none (map-get? dao-members caller)) ERR_ALREADY_MEMBER)
    (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))
    (map-set dao-members caller
      {
        stake-amount: stake-amount,
        joined-at: stacks-block-height,
        reputation: u100
      }
    )
    (ok true)
  )
)

(define-public (increase-stake (amount uint))
  (let
    (
      (caller tx-sender)
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
    )
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (map-set dao-members caller
      (merge member-data {stake-amount: (+ (get stake-amount member-data) amount)})
    )
    (ok true)
  )
)

(define-public (submit-breach-report 
  (company-name (string-ascii 100))
  (breach-description (string-ascii 500))
  (evidence-hash (string-ascii 64))
  (severity-level uint)
)
  (let
    (
      (caller tx-sender)
      (proposal-id (var-get next-proposal-id))
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
      (voting-end (+ stacks-block-height (var-get voting-period)))
      (reward-amount (* severity-level u100000))
    )
    (asserts! (<= severity-level u10) ERR_INVALID_PROPOSAL)
    (asserts! (>= (get stake-amount member-data) (var-get min-stake-amount)) ERR_INSUFFICIENT_STAKE)
    
    (map-set breach-proposals proposal-id
      {
        proposer: caller,
        company-name: company-name,
        breach-description: breach-description,
        evidence-hash: evidence-hash,
        severity-level: severity-level,
        created-at: stacks-block-height,
        voting-ends-at: voting-end,
        yes-votes: u0,
        no-votes: u0,
        total-voters: u0,
        status: "active",
        reward-pool: reward-amount
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let
    (
      (caller tx-sender)
      (proposal (unwrap! (map-get? breach-proposals proposal-id) ERR_INVALID_PROPOSAL))
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
      (vote-key {proposal-id: proposal-id, voter: caller})
      (stake-weight (get stake-amount member-data))
    )
    (asserts! (is-none (map-get? proposal-votes vote-key)) ERR_ALREADY_VOTED)
    (asserts! (< stacks-block-height (get voting-ends-at proposal)) ERR_VOTING_ENDED)
    (asserts! (is-eq (get status proposal) "active") ERR_VOTING_ENDED)
    
    (map-set proposal-votes vote-key
      {
        vote: vote,
        stake-weight: stake-weight,
        voted-at: stacks-block-height
      }
    )
    
    (map-set breach-proposals proposal-id
      (merge proposal
        {
          yes-votes: (if vote (+ (get yes-votes proposal) stake-weight) (get yes-votes proposal)),
          no-votes: (if vote (get no-votes proposal) (+ (get no-votes proposal) stake-weight)),
          total-voters: (+ (get total-voters proposal) u1)
        }
      )
    )
    (ok true)
  )
)

(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? breach-proposals proposal-id) ERR_INVALID_PROPOSAL))
      (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
      (yes-percentage (if (> total-votes u0) (/ (* (get yes-votes proposal) u100) total-votes) u0))
      (quorum-met (>= (get total-voters proposal) u3))
      (proposal-passed (and quorum-met (>= yes-percentage (var-get quorum-threshold))))
    )
    (asserts! (>= stacks-block-height (get voting-ends-at proposal)) ERR_VOTING_ACTIVE)
    (asserts! (is-eq (get status proposal) "active") ERR_VOTING_ENDED)
    
    (if proposal-passed
      (begin
        (map-set breach-proposals proposal-id (merge proposal {status: "passed"}))
        (unwrap-panic (update-company-history (get company-name proposal) (get severity-level proposal)))
        (try! (distribute-whistleblower-reward (get proposer proposal) (get reward-pool proposal)))
        (ok "passed")
      )
      (begin
        (map-set breach-proposals proposal-id (merge proposal {status: "rejected"}))
        (ok "rejected")
      )
    )
  )
)

(define-private (update-company-history (company-name (string-ascii 100)) (severity uint))
  (let
    (
      (current-history (default-to {total-breaches: u0, severity-score: u0, last-breach: u0}
                                   (map-get? company-breach-history company-name)))
    )
    (map-set company-breach-history company-name
      {
        total-breaches: (+ (get total-breaches current-history) u1),
        severity-score: (+ (get severity-score current-history) severity),
        last-breach: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-private (distribute-whistleblower-reward (whistleblower principal) (reward-amount uint))
  (let
    (
      (current-rewards (default-to u0 (map-get? whistleblower-rewards whistleblower)))
    )
    (map-set whistleblower-rewards whistleblower (+ current-rewards reward-amount))
    (as-contract (stx-transfer? reward-amount tx-sender whistleblower))
  )
)

(define-public (claim-rewards)
  (let
    (
      (caller tx-sender)
      (reward-amount (default-to u0 (map-get? whistleblower-rewards caller)))
    )
    (asserts! (> reward-amount u0) (err u121))
    (map-delete whistleblower-rewards caller)
    (as-contract (stx-transfer? reward-amount tx-sender caller))
  )
)

(define-public (update-reputation (member principal) (reputation-change int))
  (let
    (
      (member-data (unwrap! (map-get? dao-members member) ERR_NOT_MEMBER))
      (current-rep (get reputation member-data))
      (new-rep (if (> reputation-change 0) 
                   (+ current-rep (to-uint reputation-change))
                   (if (> current-rep (to-uint (- reputation-change)))
                       (- current-rep (to-uint (- reputation-change)))
                       u0)))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set dao-members member (merge member-data {reputation: new-rep}))
    (ok new-rep)
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? breach-proposals proposal-id)
)

(define-read-only (get-member-info (member principal))
  (map-get? dao-members member)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-company-history (company-name (string-ascii 100)))
  (map-get? company-breach-history company-name)
)

(define-read-only (get-pending-rewards (member principal))
  (default-to u0 (map-get? whistleblower-rewards member))
)

(define-read-only (get-dao-stats)
  {
    next-proposal-id: (var-get next-proposal-id),
    min-stake: (var-get min-stake-amount),
    voting-period: (var-get voting-period),
    quorum-threshold: (var-get quorum-threshold)
  }
)

(define-public (register-arbitrator (specialization (string-ascii 50)))
  (let
    (
      (caller tx-sender)
      (stake-amount (var-get arbitrator-min-stake))
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
    )
    (asserts! (is-none (map-get? arbitrators caller)) ERR_ALREADY_ARBITRATOR)
    (asserts! (>= (get stake-amount member-data) stake-amount) ERR_INSUFFICIENT_ARBITRATOR_STAKE)
    
    (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))
    (map-set arbitrators caller
      {
        stake-amount: stake-amount,
        cases-handled: u0,
        reputation-score: u100,
        specialization: specialization,
        joined-at: stacks-block-height,
        status: "active"
      }
    )
    (ok true)
  )
)

(define-public (file-dispute 
  (respondent principal)
  (dispute-type (string-ascii 50))
  (description (string-ascii 1000))
  (evidence-hash (string-ascii 64))
  (stake-amount uint)
)
  (let
    (
      (caller tx-sender)
      (dispute-id (var-get next-dispute-id))
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
      (mediation-deadline (+ stacks-block-height (var-get mediation-period)))
      (arbitration-deadline (+ stacks-block-height (var-get arbitration-period)))
      (appeal-deadline (+ stacks-block-height (var-get appeal-window)))
    )
    (asserts! (>= (get stake-amount member-data) stake-amount) ERR_INSUFFICIENT_STAKE)
    (asserts! (> stake-amount u0) ERR_INSUFFICIENT_STAKE)
    
    (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))
    (map-set disputes dispute-id
      {
        initiator: caller,
        respondent: respondent,
        dispute-type: dispute-type,
        description: description,
        evidence-hash: evidence-hash,
        stage: "mediation",
        created-at: stacks-block-height,
        updated-at: stacks-block-height,
        stake-amount: stake-amount,
        assigned-arbitrator: none,
        mediation-proposal: none,
        resolution: none,
        appeal-count: u0,
        final-decision: none,
        resolution-type: "pending",
        mediation-deadline: mediation-deadline,
        arbitration-deadline: arbitration-deadline,
        appeal-deadline: appeal-deadline
      }
    )
    
    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)
  )
)

(define-public (propose-mediation 
  (dispute-id uint)
  (mediation-proposal (string-ascii 500))
)
  (let
    (
      (caller tx-sender)
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    (asserts! (is-eq (get stage dispute) "mediation") ERR_DISPUTE_STAGE_MISMATCH)
    (asserts! (< stacks-block-height (get mediation-deadline dispute)) ERR_MEDIATION_FAILED)
    (asserts! (or (is-eq caller (get initiator dispute)) (is-eq caller (get respondent dispute))) ERR_NOT_AUTHORIZED)
    
    (map-set disputes dispute-id
      (merge dispute
        {
          mediation-proposal: (some mediation-proposal),
          updated-at: stacks-block-height
        }
      )
    )
    (ok true)
  )
)

(define-public (accept-mediation (dispute-id uint))
  (let
    (
      (caller tx-sender)
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    (asserts! (is-eq (get stage dispute) "mediation") ERR_DISPUTE_STAGE_MISMATCH)
    (asserts! (is-some (get mediation-proposal dispute)) ERR_INVALID_MEDIATION_PROPOSAL)
    (asserts! (or (is-eq caller (get initiator dispute)) (is-eq caller (get respondent dispute))) ERR_NOT_AUTHORIZED)
    
    (map-set disputes dispute-id
      (merge dispute
        {
          stage: "resolved",
          resolution-type: "mediation",
          resolution: (get mediation-proposal dispute),
          final-decision: (get mediation-proposal dispute),
          updated-at: stacks-block-height
        }
      )
    )
    (try! (as-contract (stx-transfer? (get stake-amount dispute) tx-sender (get initiator dispute))))
    (ok true)
  )
)

(define-public (escalate-to-arbitration (dispute-id uint))
  (let
    (
      (caller tx-sender)
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
    )
    (asserts! (is-eq (get stage dispute) "mediation") ERR_DISPUTE_STAGE_MISMATCH)
    (asserts! (>= stacks-block-height (get mediation-deadline dispute)) ERR_INVALID_DISPUTE_STAGE)
    (asserts! (or (is-eq caller (get initiator dispute)) (is-eq caller (get respondent dispute))) ERR_NOT_AUTHORIZED)
    
    (let
      (
        (selected-arbitrator (select-arbitrator (get dispute-type dispute)))
      )
      (map-set disputes dispute-id
        (merge dispute
          {
            stage: "arbitration",
            assigned-arbitrator: selected-arbitrator,
            updated-at: stacks-block-height
          }
        )
      )
      (ok true)
    )
  )
)

(define-public (submit-arbitration-decision 
  (dispute-id uint)
  (decision (string-ascii 500))
  (winner principal)
)
  (let
    (
      (caller tx-sender)
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
      (arbitrator-data (unwrap! (map-get? arbitrators caller) ERR_NOT_ARBITRATOR))
    )
    (asserts! (is-eq (get stage dispute) "arbitration") ERR_DISPUTE_STAGE_MISMATCH)
    (asserts! (is-eq (some caller) (get assigned-arbitrator dispute)) ERR_NOT_AUTHORIZED)
    (asserts! (< stacks-block-height (get arbitration-deadline dispute)) ERR_VOTING_ENDED)
    
    (map-set disputes dispute-id
      (merge dispute
        {
          stage: "resolved",
          resolution-type: "arbitration",
          resolution: (some decision),
          final-decision: (some decision),
          updated-at: stacks-block-height
        }
      )
    )
    
    (map-set arbitrators caller
      (merge arbitrator-data
        {
          cases-handled: (+ (get cases-handled arbitrator-data) u1),
          reputation-score: (+ (get reputation-score arbitrator-data) u10)
        }
      )
    )
    
    (try! (as-contract (stx-transfer? (get stake-amount dispute) tx-sender winner)))
    (ok true)
  )
)

(define-public (file-appeal 
  (dispute-id uint)
  (appeal-reason (string-ascii 500))
  (appeal-evidence (string-ascii 64))
  (appeal-fee uint)
)
  (let
    (
      (caller tx-sender)
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
    )
    (asserts! (is-eq (get stage dispute) "resolved") ERR_DISPUTE_STAGE_MISMATCH)
    (asserts! (< stacks-block-height (get appeal-deadline dispute)) ERR_APPEAL_WINDOW_CLOSED)
    (asserts! (or (is-eq caller (get initiator dispute)) (is-eq caller (get respondent dispute))) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get stake-amount member-data) appeal-fee) ERR_INSUFFICIENT_STAKE)
    
    (try! (stx-transfer? appeal-fee caller (as-contract tx-sender)))
    (map-set dispute-appeals dispute-id
      {
        appellant: caller,
        appeal-reason: appeal-reason,
        appeal-evidence: appeal-evidence,
        appeal-fee: appeal-fee,
        appeal-stage: "pending",
        created-at: stacks-block-height,
        panel-decision: none
      }
    )
    
    (map-set disputes dispute-id
      (merge dispute
        {
          stage: "appeal",
          appeal-count: (+ (get appeal-count dispute) u1),
          updated-at: stacks-block-height
        }
      )
    )
    (ok true)
  )
)

(define-public (vote-on-appeal (dispute-id uint) (support-resolution bool))
  (let
    (
      (caller tx-sender)
      (dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
      (member-data (unwrap! (map-get? dao-members caller) ERR_NOT_MEMBER))
      (vote-key {dispute-id: dispute-id, voter: caller})
    )
    (asserts! (is-eq (get stage dispute) "appeal") ERR_DISPUTE_STAGE_MISMATCH)
    (asserts! (is-none (map-get? dispute-votes vote-key)) ERR_ALREADY_VOTED)
    
    (map-set dispute-votes vote-key
      {
        resolution-support: support-resolution,
        voted-at: stacks-block-height,
        vote-weight: (get stake-amount member-data)
      }
    )
    (ok true)
  )
)

(define-private (select-arbitrator (dispute-type (string-ascii 50)))
  (let
    (
      (arbitrator-list (get-qualified-arbitrators dispute-type))
    )
    (if (> (len arbitrator-list) u0)
      (some (unwrap-panic (element-at arbitrator-list u0)))
      none
    )
  )
)

(define-private (get-qualified-arbitrators (dispute-type (string-ascii 50)))
  (list tx-sender)
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

(define-read-only (get-arbitrator-info (arbitrator principal))
  (map-get? arbitrators arbitrator)
)

(define-read-only (get-dispute-appeal (dispute-id uint))
  (map-get? dispute-appeals dispute-id)
)

(define-read-only (get-dispute-vote (dispute-id uint) (voter principal))
  (map-get? dispute-votes {dispute-id: dispute-id, voter: voter})
)

(define-read-only (calculate-voting-power (member principal))
  (let
    (
      (member-data (map-get? dao-members member))
    )
    (match member-data
      member-info (* (get stake-amount member-info) (get reputation member-info))
      u0
    )
  )
)