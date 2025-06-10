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

(define-data-var next-proposal-id uint u1)
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
    (asserts! (> reward-amount u0) (err u109))
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