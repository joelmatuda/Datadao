;; Anonymous Tip Verification System for DataDAO
;; Enables anonymous preliminary tip submission and verification

(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_TIP_NOT_FOUND (err u301))
(define-constant ERR_TIP_EXPIRED (err u302))
(define-constant ERR_ALREADY_VERIFIED (err u303))
(define-constant ERR_INVALID_COMMITMENT (err u304))
(define-constant ERR_VERIFICATION_FAILED (err u305))
(define-constant ERR_TIP_NOT_VERIFIED (err u306))
(define-constant ERR_INSUFFICIENT_STAKE (err u307))
(define-constant ERR_TIP_ALREADY_CLAIMED (err u308))
(define-constant ERR_INVALID_SEVERITY (err u309))
(define-constant ERR_COMMITMENT_PERIOD_ACTIVE (err u310))

;; Data variables
(define-data-var next-tip-id uint u1)
(define-data-var min-verification-stake uint u100000)
(define-data-var tip-lifetime-blocks uint u1440) ;; ~10 days
(define-data-var commitment-period uint u288) ;; ~2 days
(define-data-var verification-reward-rate uint u10) ;; 10% of tip stake

;; Anonymous tips with commitment-reveal scheme
(define-map anonymous-tips uint
  {
    commitment-hash: (buff 32), ;; SHA256 of (tip-content + nonce)
    severity-level: uint,
    company-hint: (string-ascii 50), ;; Partial company name for indexing
    created-at: uint,
    expires-at: uint,
    reveal-deadline: uint,
    status: (string-ascii 20),
    verification-count: uint,
    verification-threshold: uint,
    tip-stake: uint,
    revealed-content: (optional (string-ascii 1000)),
    evidence-hash: (optional (buff 32))
  }
)

;; Tip verifications by members
(define-map tip-verifications {tip-id: uint, verifier: principal}
  {
    credibility-score: uint, ;; 1-10 scale
    verification-notes: (string-ascii 200),
    verifier-stake: uint,
    verified-at: uint,
    vote-weight: uint
  }
)

;; Track verifier reputation for tip verification
(define-map verifier-reputation principal
  {
    tips-verified: uint,
    accuracy-score: uint, ;; Running average of verification accuracy
    reputation-level: uint,
    total-stake-committed: uint,
    successful-verifications: uint
  }
)

;; Tip reveal registry (commitment -> revealed data)
(define-map tip-reveals (buff 32)
  {
    revealer: principal,
    tip-content: (string-ascii 1000),
    evidence-hash: (buff 32),
    nonce: (buff 16),
    revealed-at: uint
  }
)

;; Create anonymous tip with commitment
(define-public (submit-anonymous-tip 
  (commitment-hash (buff 32))
  (severity-level uint)
  (company-hint (string-ascii 50))
  (tip-stake uint))
  (let (
    (tip-id (var-get next-tip-id))
    (expires-at (+ stacks-block-height (var-get tip-lifetime-blocks)))
    (reveal-deadline (+ stacks-block-height (var-get commitment-period)))
    (threshold (if (>= severity-level u7) u5 u3))
  )
    ;; Validations
    (asserts! (<= severity-level u10) ERR_INVALID_SEVERITY)
    (asserts! (> tip-stake u50000) ERR_INSUFFICIENT_STAKE) ;; Min 0.05 STX
    
    ;; Transfer stake to contract
    (try! (stx-transfer? tip-stake tx-sender (as-contract tx-sender)))
    
    ;; Create tip record
    (map-set anonymous-tips tip-id {
      commitment-hash: commitment-hash,
      severity-level: severity-level,
      company-hint: company-hint,
      created-at: stacks-block-height,
      expires-at: expires-at,
      reveal-deadline: reveal-deadline,
      status: "committed",
      verification-count: u0,
      verification-threshold: threshold,
      tip-stake: tip-stake,
      revealed-content: none,
      evidence-hash: none
    })
    
    (var-set next-tip-id (+ tip-id u1))
    (ok tip-id)
  )
)

;; Reveal tip content (commitment-reveal phase)
(define-public (reveal-tip-content 
  (tip-id uint)
  (tip-content (string-ascii 1000))
  (evidence-hash (buff 32))
  (nonce (buff 16)))
  (let (
    (tip (unwrap! (map-get? anonymous-tips tip-id) ERR_TIP_NOT_FOUND))
    (computed-hash (sha256 (concat (concat (unwrap-panic (to-consensus-buff? tip-content)) evidence-hash) nonce)))
  )
    ;; Validate reveal timing and commitment
    (asserts! (is-eq (get status tip) "committed") ERR_ALREADY_VERIFIED)
    (asserts! (< stacks-block-height (get reveal-deadline tip)) ERR_TIP_EXPIRED)
    (asserts! (is-eq computed-hash (get commitment-hash tip)) ERR_INVALID_COMMITMENT)
    
    ;; Store reveal data
    (map-set tip-reveals (get commitment-hash tip) {
      revealer: tx-sender,
      tip-content: tip-content,
      evidence-hash: evidence-hash,
      nonce: nonce,
      revealed-at: stacks-block-height
    })
    
    ;; Update tip with revealed content
    (map-set anonymous-tips tip-id 
      (merge tip {
        status: "revealed",
        revealed-content: (some tip-content),
        evidence-hash: (some evidence-hash)
      }))
    
    (ok true)
  )
)

;; Verify revealed tip credibility
(define-public (verify-tip-credibility 
  (tip-id uint)
  (credibility-score uint)
  (verification-notes (string-ascii 200)))
  (let (
    (tip (unwrap! (map-get? anonymous-tips tip-id) ERR_TIP_NOT_FOUND))
    (member-data (unwrap! (contract-call? .Datadao get-member-info tx-sender) ERR_UNAUTHORIZED))
    (verification-key {tip-id: tip-id, verifier: tx-sender})
    (stake-amount (var-get min-verification-stake))
    (vote-weight (get stake-amount member-data))
  )
    ;; Validations
    (asserts! (is-eq (get status tip) "revealed") ERR_TIP_NOT_VERIFIED)
    (asserts! (< stacks-block-height (get expires-at tip)) ERR_TIP_EXPIRED)
    (asserts! (is-none (map-get? tip-verifications verification-key)) ERR_ALREADY_VERIFIED)
    (asserts! (<= credibility-score u10) ERR_VERIFICATION_FAILED)
    (asserts! (>= (get stake-amount member-data) stake-amount) ERR_INSUFFICIENT_STAKE)
    
    ;; Transfer verification stake
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Record verification
    (map-set tip-verifications verification-key {
      credibility-score: credibility-score,
      verification-notes: verification-notes,
      verifier-stake: stake-amount,
      verified-at: stacks-block-height,
      vote-weight: vote-weight
    })
    
    ;; Update tip verification count
    (map-set anonymous-tips tip-id 
      (merge tip {verification-count: (+ (get verification-count tip) u1)}))
    
    ;; Check if threshold reached for finalization
    (let (
      (new-count (+ (get verification-count tip) u1))
    )
      (if (>= new-count (get verification-threshold tip))
        (unwrap-panic (finalize-tip-verification tip-id))
        false
      )
    )
    
    ;; Update verifier reputation
    (unwrap-panic (update-verifier-reputation tx-sender credibility-score))
    (ok true)
  )
)

;; Finalize tip verification and determine credibility
(define-private (finalize-tip-verification (tip-id uint))
  (let (
    (tip (unwrap! (map-get? anonymous-tips tip-id) ERR_TIP_NOT_FOUND))
    (avg-credibility (calculate-average-credibility tip-id))
    (is-credible (>= avg-credibility u6))
  )
    ;; Update tip status based on verification results
    (map-set anonymous-tips tip-id 
      (merge tip {
        status: (if is-credible "verified" "rejected")
      }))
    
    ;; Distribute rewards if tip is credible
    (if is-credible
      (begin
        (unwrap-panic (distribute-verification-rewards tip-id))
        (ok true)
      )
      (ok false)
    )
  )
)

;; Promote verified tip to formal breach proposal
(define-public (promote-to-proposal (tip-id uint))
  (let (
    (tip (unwrap! (map-get? anonymous-tips tip-id) ERR_TIP_NOT_FOUND))
    (reveal-data (unwrap! (map-get? tip-reveals (get commitment-hash tip)) ERR_TIP_NOT_VERIFIED))
  )
    ;; Validate tip eligibility for promotion
    (asserts! (is-eq (get status tip) "verified") ERR_TIP_NOT_VERIFIED)
    (asserts! (is-eq tx-sender (get revealer reveal-data)) ERR_UNAUTHORIZED)
    
    ;; Create formal breach proposal using tip data  
    (let (
      (tip-content-truncated (unwrap-panic (as-max-len? (get tip-content reveal-data) u500)))
      (evidence-hex "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
      (proposal-result (contract-call? .Datadao submit-breach-report
        (get company-hint tip)
        tip-content-truncated
        evidence-hex
        (get severity-level tip)
      ))
    )
      ;; Mark tip as promoted
      (map-set anonymous-tips tip-id 
        (merge tip {status: "promoted"}))
      
      ;; Return proposal ID if successful
      (match proposal-result
        success-result (ok success-result)
        error-result (err u999)
      )
    )
  )
)

;; Helper functions
(define-private (calculate-average-credibility (tip-id uint))
  ;; Simplified calculation - in production would iterate through all verifications
  ;; and compute weighted average based on verifier stake and reputation
  u7 ;; Mock average credibility score
)

(define-private (distribute-verification-rewards (tip-id uint))
  (let (
    (tip (unwrap! (map-get? anonymous-tips tip-id) ERR_TIP_NOT_FOUND))
    (reward-per-verifier (/ (* (get tip-stake tip) (var-get verification-reward-rate)) u100))
  )
    ;; Simplified reward distribution - would iterate through all verifiers
    (as-contract (stx-transfer? reward-per-verifier tx-sender tx-sender))
  )
)

(define-private (update-verifier-reputation (verifier principal) (credibility-score uint))
  (let (
    (current-rep (default-to {
      tips-verified: u0,
      accuracy-score: u5,
      reputation-level: u1,
      total-stake-committed: u0,
      successful-verifications: u0
    } (map-get? verifier-reputation verifier)))
  )
    (map-set verifier-reputation verifier 
      (merge current-rep {
        tips-verified: (+ (get tips-verified current-rep) u1),
        accuracy-score: (/ (+ (get accuracy-score current-rep) credibility-score) u2),
        total-stake-committed: (+ (get total-stake-committed current-rep) (var-get min-verification-stake)),
        successful-verifications: (+ (get successful-verifications current-rep) (if (>= credibility-score u6) u1 u0))
      }))
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-tip (tip-id uint))
  (map-get? anonymous-tips tip-id)
)

(define-read-only (get-tip-verification (tip-id uint) (verifier principal))
  (map-get? tip-verifications {tip-id: tip-id, verifier: verifier})
)

(define-read-only (get-verifier-reputation (verifier principal))
  (map-get? verifier-reputation verifier)
)

(define-read-only (get-tip-reveal (commitment-hash (buff 32)))
  (map-get? tip-reveals commitment-hash)
)

(define-read-only (get-tip-stats)
  {
    total-tips: (- (var-get next-tip-id) u1),
    min-verification-stake: (var-get min-verification-stake),
    tip-lifetime: (var-get tip-lifetime-blocks),
    commitment-period: (var-get commitment-period)
  }
)
