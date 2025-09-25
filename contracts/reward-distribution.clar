;; TreeGrow Reward Distribution Contract
;; This contract manages token distribution and incentive mechanisms
;; Handles rewards, achievements, and community incentives

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u501))
(define-constant ERR-INVALID-AMOUNT (err u502))
(define-constant ERR-REWARD-NOT-FOUND (err u503))
(define-constant ERR-ALREADY-CLAIMED (err u504))
(define-constant ERR-INSUFFICIENT-BALANCE (err u505))
(define-constant ERR-INVALID-ACHIEVEMENT (err u506))
(define-constant ERR-CAMPAIGN-NOT-ACTIVE (err u507))
(define-constant ERR-INVALID-POOL (err u508))
(define-constant ERR-POOL-DEPLETED (err u509))

;; Data structures
(define-map reward-pools
  { pool-id: uint }
  {
    pool-name: (string-ascii 50),
    total-allocation: uint,
    remaining-balance: uint,
    reward-rate: uint,
    is-active: bool,
    created-by: principal,
    expiry-block: uint
  }
)

(define-map user-achievements
  { user: principal, achievement-id: uint }
  {
    achievement-name: (string-ascii 100),
    earned-date: uint,
    reward-amount: uint,
    is-claimed: bool,
    milestone-level: uint
  }
)

(define-map achievement-definitions
  { achievement-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 200),
    reward-amount: uint,
    requirement-type: (string-ascii 30),
    requirement-value: uint,
    is-active: bool,
    badge-icon: (string-ascii 64)
  }
)

(define-map seasonal-campaigns
  { campaign-id: uint }
  {
    campaign-name: (string-ascii 50),
    start-block: uint,
    end-block: uint,
    bonus-multiplier: uint,
    target-species: (optional (string-ascii 50)),
    total-budget: uint,
    spent-budget: uint,
    is-active: bool
  }
)

(define-map validator-rewards
  { validator: principal, period: uint }
  {
    validations-count: uint,
    accuracy-rate: uint,
    base-reward: uint,
    bonus-reward: uint,
    total-earned: uint,
    is-claimed: bool
  }
)

(define-map community-pools
  { pool-name: (string-ascii 50) }
  {
    pool-balance: uint,
    contributors: uint,
    distribution-rate: uint,
    last-distribution: uint,
    is-active: bool
  }
)

(define-map user-referrals
  { referrer: principal, referred: principal }
  {
    referral-date: uint,
    bonus-earned: uint,
    trees-planted: uint,
    is-active: bool
  }
)

;; Variables
(define-data-var next-pool-id uint u1)
(define-data-var next-achievement-id uint u1)
(define-data-var next-campaign-id uint u1)
(define-data-var validator-reward-period uint u4032) ;; approximately 1 month
(define-data-var referral-bonus uint u50)
(define-data-var community-fund-balance uint u0)
(define-data-var weekly-distribution-rate uint u100)

;; Initialize achievement definitions
(map-set achievement-definitions
  { achievement-id: u1 }
  {
    name: "First Tree",
    description: "Plant your first tree and help the environment",
    reward-amount: u100,
    requirement-type: "trees_planted",
    requirement-value: u1,
    is-active: true,
    badge-icon: "first_tree_badge"
  }
)

(map-set achievement-definitions
  { achievement-id: u2 }
  {
    name: "Forest Builder",
    description: "Plant 10 trees and become a forest builder",
    reward-amount: u500,
    requirement-type: "trees_planted",
    requirement-value: u10,
    is-active: true,
    badge-icon: "forest_builder_badge"
  }
)

(map-set achievement-definitions
  { achievement-id: u3 }
  {
    name: "Green Warrior",
    description: "Plant 50 trees and join the green warriors",
    reward-amount: u2000,
    requirement-type: "trees_planted",
    requirement-value: u50,
    is-active: true,
    badge-icon: "green_warrior_badge"
  }
)

(map-set achievement-definitions
  { achievement-id: u4 }
  {
    name: "Validation Expert",
    description: "Complete 100 tree validations with 90% accuracy",
    reward-amount: u1000,
    requirement-type: "validations_completed",
    requirement-value: u100,
    is-active: true,
    badge-icon: "validation_expert_badge"
  }
)

;; Initialize community pools
(map-set community-pools
  { pool-name: "conservation" }
  {
    pool-balance: u10000,
    contributors: u0,
    distribution-rate: u50,
    last-distribution: u0,
    is-active: true
  }
)

(map-set community-pools
  { pool-name: "research" }
  {
    pool-balance: u5000,
    contributors: u0,
    distribution-rate: u25,
    last-distribution: u0,
    is-active: true
  }
)

;; Public functions

;; Create a new reward pool (admin/sponsors)
(define-public (create-reward-pool (pool-name (string-ascii 50)) (allocation uint) (reward-rate uint) (expiry-blocks uint))
  (let (
    (pool-id (var-get next-pool-id))
    (creator tx-sender)
  )
    (asserts! (> allocation u0) ERR-INVALID-AMOUNT)
    (asserts! (> reward-rate u0) ERR-INVALID-AMOUNT)
    
    (map-set reward-pools
      { pool-id: pool-id }
      {
        pool-name: pool-name,
        total-allocation: allocation,
        remaining-balance: allocation,
        reward-rate: reward-rate,
        is-active: true,
        created-by: creator,
        expiry-block: (+ u0 expiry-blocks)
      }
    )
    
    (var-set next-pool-id (+ pool-id u1))
    (ok pool-id)
  )
)

;; Claim achievement reward
(define-public (claim-achievement-reward (achievement-id uint))
  (let (
    (user tx-sender)
    (achievement (unwrap! (map-get? user-achievements { user: user, achievement-id: achievement-id }) ERR-REWARD-NOT-FOUND))
  )
    (asserts! (not (get is-claimed achievement)) ERR-ALREADY-CLAIMED)
    
    ;; Mark achievement as claimed
    (map-set user-achievements
      { user: user, achievement-id: achievement-id }
      (merge achievement { is-claimed: true })
    )
    
    ;; Process reward - in full implementation this would mint tokens
    (ok (get reward-amount achievement))
  )
)

;; Award achievement to user (called by other contracts)
(define-public (award-achievement (user principal) (achievement-id uint) (milestone-level uint))
  (let (
    (achievement-def (unwrap! (map-get? achievement-definitions { achievement-id: achievement-id }) ERR-INVALID-ACHIEVEMENT))
  )
    (asserts! (get is-active achievement-def) ERR-INVALID-ACHIEVEMENT)
    
    ;; Check if user already has this achievement
    (match (map-get? user-achievements { user: user, achievement-id: achievement-id })
      existing-achievement ERR-ALREADY-CLAIMED
      (begin
        ;; Award the achievement
        (map-set user-achievements
          { user: user, achievement-id: achievement-id }
          {
            achievement-name: (get name achievement-def),
            earned-date: u0,
            reward-amount: (get reward-amount achievement-def),
            is-claimed: false,
            milestone-level: milestone-level
          }
        )
        (ok true)
      )
    )
  )
)

;; Create seasonal campaign
(define-public (create-seasonal-campaign (name (string-ascii 50)) (duration-blocks uint) (bonus-multiplier uint) (target-species (optional (string-ascii 50))) (budget uint))
  (let (
    (campaign-id (var-get next-campaign-id))
    (creator tx-sender)
  )
    (asserts! (> duration-blocks u0) ERR-INVALID-AMOUNT)
    (asserts! (> bonus-multiplier u100) ERR-INVALID-AMOUNT) ;; Bonus should be > 100% (1.0x)
    (asserts! (> budget u0) ERR-INVALID-AMOUNT)
    
    (map-set seasonal-campaigns
      { campaign-id: campaign-id }
      {
        campaign-name: name,
        start-block: u0,
        end-block: (+ u0 duration-blocks),
        bonus-multiplier: bonus-multiplier,
        target-species: target-species,
        total-budget: budget,
        spent-budget: u0,
        is-active: true
      }
    )
    
    (var-set next-campaign-id (+ campaign-id u1))
    (ok campaign-id)
  )
)

;; Distribute validator rewards for a period
(define-public (distribute-validator-rewards (validator principal) (period uint) (validations-count uint) (accuracy-rate uint))
  (let (
    (base-reward (* validations-count u10))
    (accuracy-bonus (if (>= accuracy-rate u90) u100 u0))
    (total-reward (+ base-reward accuracy-bonus))
  )
    (asserts! (> validations-count u0) ERR-INVALID-AMOUNT)
    (asserts! (<= accuracy-rate u100) ERR-INVALID-AMOUNT)
    
    ;; Check if rewards already distributed for this period
    (match (map-get? validator-rewards { validator: validator, period: period })
      existing-reward ERR-ALREADY-CLAIMED
      (begin
        (map-set validator-rewards
          { validator: validator, period: period }
          {
            validations-count: validations-count,
            accuracy-rate: accuracy-rate,
            base-reward: base-reward,
            bonus-reward: accuracy-bonus,
            total-earned: total-reward,
            is-claimed: false
          }
        )
        (ok total-reward)
      )
    )
  )
)

;; Claim validator rewards
(define-public (claim-validator-rewards (period uint))
  (let (
    (validator tx-sender)
    (reward (unwrap! (map-get? validator-rewards { validator: validator, period: period }) ERR-REWARD-NOT-FOUND))
  )
    (asserts! (not (get is-claimed reward)) ERR-ALREADY-CLAIMED)
    
    ;; Mark as claimed
    (map-set validator-rewards
      { validator: validator, period: period }
      (merge reward { is-claimed: true })
    )
    
    (ok (get total-earned reward))
  )
)

;; Contribute to community pool
(define-public (contribute-to-community-pool (pool-name (string-ascii 50)) (amount uint))
  (let (
    (contributor tx-sender)
    (pool (unwrap! (map-get? community-pools { pool-name: pool-name }) ERR-INVALID-POOL))
  )
    (asserts! (get is-active pool) ERR-CAMPAIGN-NOT-ACTIVE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update pool
    (map-set community-pools
      { pool-name: pool-name }
      (merge pool {
        pool-balance: (+ (get pool-balance pool) amount),
        contributors: (+ (get contributors pool) u1)
      })
    )
    
    (ok true)
  )
)

;; Create referral link
(define-public (create-referral (referred-user principal))
  (let (
    (referrer tx-sender)
  )
    (asserts! (not (is-eq referrer referred-user)) ERR-NOT-AUTHORIZED)
    
    ;; Check if referral already exists
    (match (map-get? user-referrals { referrer: referrer, referred: referred-user })
      existing-referral ERR-ALREADY-CLAIMED
      (begin
        (map-set user-referrals
          { referrer: referrer, referred: referred-user }
          {
            referral-date: u0,
            bonus-earned: u0,
            trees-planted: u0,
            is-active: true
          }
        )
        (ok true)
      )
    )
  )
)

;; Process referral bonus when referred user plants tree
(define-public (process-referral-bonus (referrer principal) (referred-user principal))
  (let (
    (referral (unwrap! (map-get? user-referrals { referrer: referrer, referred: referred-user }) ERR-REWARD-NOT-FOUND))
    (bonus-amount (var-get referral-bonus))
  )
    (asserts! (get is-active referral) ERR-CAMPAIGN-NOT-ACTIVE)
    
    ;; Update referral stats
    (map-set user-referrals
      { referrer: referrer, referred: referred-user }
      (merge referral {
        bonus-earned: (+ (get bonus-earned referral) bonus-amount),
        trees-planted: (+ (get trees-planted referral) u1)
      })
    )
    
    (ok bonus-amount)
  )
)

;; Read-only functions

;; Get reward pool information
(define-read-only (get-reward-pool (pool-id uint))
  (map-get? reward-pools { pool-id: pool-id })
)

;; Get user achievement
(define-read-only (get-user-achievement (user principal) (achievement-id uint))
  (map-get? user-achievements { user: user, achievement-id: achievement-id })
)

;; Get achievement definition
(define-read-only (get-achievement-definition (achievement-id uint))
  (map-get? achievement-definitions { achievement-id: achievement-id })
)

;; Get seasonal campaign
(define-read-only (get-seasonal-campaign (campaign-id uint))
  (map-get? seasonal-campaigns { campaign-id: campaign-id })
)

;; Get validator rewards
(define-read-only (get-validator-rewards (validator principal) (period uint))
  (map-get? validator-rewards { validator: validator, period: period })
)

;; Get community pool information
(define-read-only (get-community-pool (pool-name (string-ascii 50)))
  (map-get? community-pools { pool-name: pool-name })
)

;; Get referral information
(define-read-only (get-referral-info (referrer principal) (referred principal))
  (map-get? user-referrals { referrer: referrer, referred: referred })
)

;; Get community fund balance
(define-read-only (get-community-fund-balance)
  (var-get community-fund-balance)
)

;; Check if campaign is active
(define-read-only (is-campaign-active (campaign-id uint))
  (match (map-get? seasonal-campaigns { campaign-id: campaign-id })
    campaign (and (get is-active campaign) (<= u0 (get end-block campaign)))
    false
  )
)

;; Calculate campaign bonus for tree planting
(define-read-only (calculate-campaign-bonus (campaign-id uint) (base-reward uint))
  (match (map-get? seasonal-campaigns { campaign-id: campaign-id })
    campaign
    (if (and (get is-active campaign) (<= u0 (get end-block campaign)))
      (/ (* base-reward (get bonus-multiplier campaign)) u100)
      base-reward
    )
    base-reward
  )
)

;; Get next available IDs
(define-read-only (get-next-pool-id)
  (var-get next-pool-id)
)

(define-read-only (get-next-achievement-id)
  (var-get next-achievement-id)
)

(define-read-only (get-next-campaign-id)
  (var-get next-campaign-id)
)

;; Private functions

;; Calculate reward with bonuses
(define-private (calculate-total-reward (base-reward uint) (campaign-bonus uint) (bonus-amount uint))
  (+ base-reward campaign-bonus bonus-amount)
)

;; Check if user qualifies for achievement
(define-private (check-achievement-eligibility (user principal) (achievement-id uint) (current-stats uint))
  (match (map-get? achievement-definitions { achievement-id: achievement-id })
    achievement-def
    (>= current-stats (get requirement-value achievement-def))
    false
  )
)

;; Distribute weekly community rewards
(define-private (distribute-community-rewards (pool-name (string-ascii 50)))
  (match (map-get? community-pools { pool-name: pool-name })
    pool
    (let ((distribution-amount (* (get contributors pool) (get distribution-rate pool))))
      (if (and (get is-active pool) (>= (get pool-balance pool) distribution-amount))
        (begin
          (map-set community-pools
            { pool-name: pool-name }
            (merge pool {
              pool-balance: (- (get pool-balance pool) distribution-amount),
              last-distribution: u0
            })
          )
          distribution-amount
        )
        u0
      )
    )
    u0
  )
)


