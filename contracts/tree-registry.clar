;; TreeGrow Tree Registry Contract
;; This contract manages the core tree planting and tracking system
;; Users can register tree plantings and track their growth over time

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-INVALID-SPECIES (err u402))
(define-constant ERR-INVALID-LOCATION (err u403))
(define-constant ERR-TREE-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-VERIFIED (err u405))
(define-constant ERR-INSUFFICIENT-STAKE (err u406))
(define-constant ERR-USER-NOT-REGISTERED (err u407))
(define-constant ERR-INVALID-PROOF (err u408))
(define-constant ERR-TREE-ALREADY-DEAD (err u409))

;; Token definition
(define-fungible-token grow-reward)

;; Data structures
(define-map planters
  { address: principal }
  {
    total-trees-planted: uint,
    total-trees-alive: uint,
    reputation-score: uint,
    registration-date: uint,
    is-active: bool
  }
)

(define-map trees
  { tree-id: uint }
  {
    planter: principal,
    species: (string-ascii 50),
    latitude: (string-ascii 20),
    longitude: (string-ascii 20),
    planting-date: uint,
    verification-status: (string-ascii 20),
    verifier: (optional principal),
    survival-status: (string-ascii 20),
    last-check-date: uint,
    reward-claimed: bool,
    carbon-offset: uint
  }
)

(define-map species-info
  { species-name: (string-ascii 50) }
  {
    base-reward: uint,
    carbon-per-year: uint,
    survival-rate: uint,
    growth-period: uint,
    is-native: bool,
    is-active: bool
  }
)

(define-map validators
  { address: principal }
  {
    total-validations: uint,
    successful-validations: uint,
    stake-amount: uint,
    is-authorized: bool,
    reputation: uint
  }
)

(define-map tree-checkups
  { tree-id: uint, check-date: uint }
  {
    checker: principal,
    health-status: (string-ascii 20),
    growth-stage: uint,
    notes: (string-ascii 200),
    photo-hash: (string-ascii 64)
  }
)

;; Variables
(define-data-var next-tree-id uint u1)
(define-data-var total-supply uint u0)
(define-data-var min-validator-stake uint u1000)
(define-data-var base-planting-reward uint u100)
(define-data-var verification-period uint u2016) ;; approximately 2 weeks in blocks
(define-data-var checkup-interval uint u4032) ;; approximately 1 month in blocks

;; Initialize species information
(map-set species-info
  { species-name: "oak" }
  {
    base-reward: u200,
    carbon-per-year: u48,
    survival-rate: u85,
    growth-period: u50,
    is-native: true,
    is-active: true
  }
)

(map-set species-info
  { species-name: "pine" }
  {
    base-reward: u150,
    carbon-per-year: u35,
    survival-rate: u80,
    growth-period: u30,
    is-native: true,
    is-active: true
  }
)

(map-set species-info
  { species-name: "maple" }
  {
    base-reward: u180,
    carbon-per-year: u40,
    survival-rate: u82,
    growth-period: u40,
    is-native: true,
    is-active: true
  }
)

(map-set species-info
  { species-name: "willow" }
  {
    base-reward: u120,
    carbon-per-year: u30,
    survival-rate: u90,
    growth-period: u15,
    is-native: false,
    is-active: true
  }
)

;; Public functions

;; Register as a tree planter
(define-public (register-planter)
  (let ((user tx-sender))
    (match (map-get? planters { address: user })
      existing-planter ERR-NOT-AUTHORIZED
      (begin
        (map-set planters
          { address: user }
          {
            total-trees-planted: u0,
            total-trees-alive: u0,
            reputation-score: u100,
            registration-date: u0,
            is-active: true
          }
        )
        (ok true)
      )
    )
  )
)

;; Plant a new tree
(define-public (plant-tree (species (string-ascii 50)) (latitude (string-ascii 20)) (longitude (string-ascii 20)) (photo-hash (string-ascii 64)))
  (let (
    (tree-id (var-get next-tree-id))
    (planter tx-sender)
  )
    (asserts! (is-planter-registered planter) ERR-USER-NOT-REGISTERED)
    (asserts! (is-valid-species species) ERR-INVALID-SPECIES)
    (asserts! (>= (len latitude) u5) ERR-INVALID-LOCATION)
    (asserts! (>= (len longitude) u5) ERR-INVALID-LOCATION)
    (asserts! (>= (len photo-hash) u32) ERR-INVALID-PROOF)
    
    ;; Create tree record
    (map-set trees
      { tree-id: tree-id }
      {
        planter: planter,
        species: species,
        latitude: latitude,
        longitude: longitude,
        planting-date: u0,
        verification-status: "pending",
        verifier: none,
        survival-status: "planted",
        last-check-date: u0,
        reward-claimed: false,
        carbon-offset: u0
      }
    )
    
    ;; Update planter statistics
    (update-planter-stats planter u1 u0)
    
    (var-set next-tree-id (+ tree-id u1))
    (ok tree-id)
  )
)

;; Verify a tree planting (validators only)
(define-public (verify-tree (tree-id uint) (approved bool))
  (let (
    (validator tx-sender)
    (tree (unwrap! (map-get? trees { tree-id: tree-id }) ERR-TREE-NOT-FOUND))
  )
    (asserts! (is-authorized-validator validator) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get verification-status tree) "pending") ERR-ALREADY-VERIFIED)
    
    (if approved
      (begin
        ;; Update tree as verified
        (map-set trees
          { tree-id: tree-id }
          (merge tree {
            verification-status: "verified",
            verifier: (some validator)
          })
        )
        ;; Update validator stats
        (update-validator-stats validator true)
        ;; Process initial reward
        (try! (process-planting-reward tree-id tree))
      )
      (begin
        ;; Reject the tree
        (map-set trees
          { tree-id: tree-id }
          (merge tree {
            verification-status: "rejected",
            verifier: (some validator)
          })
        )
        ;; Update validator stats
        (update-validator-stats validator false)
        ;; Update planter stats (remove from count)
        (update-planter-stats (get planter tree) (- u0 u1) u0)
      )
    )
    (ok approved)
  )
)

;; Stake tokens to become a validator
(define-public (become-validator)
  (let ((user tx-sender))
    (asserts! (is-planter-registered user) ERR-USER-NOT-REGISTERED)
    (asserts! (>= (ft-get-balance grow-reward user) (var-get min-validator-stake)) ERR-INSUFFICIENT-STAKE)
    
    ;; Burn stake tokens
    (try! (ft-burn? grow-reward (var-get min-validator-stake) user))
    
    (map-set validators
      { address: user }
      {
        total-validations: u0,
        successful-validations: u0,
        stake-amount: (var-get min-validator-stake),
        is-authorized: true,
        reputation: u100
      }
    )
    (ok true)
  )
)

;; Check on tree health (validators and planters)
(define-public (check-tree-health (tree-id uint) (health-status (string-ascii 20)) (growth-stage uint) (notes (string-ascii 200)) (photo-hash (string-ascii 64)))
  (let (
    (checker tx-sender)
    (tree (unwrap! (map-get? trees { tree-id: tree-id }) ERR-TREE-NOT-FOUND))
    (check-date u0)
  )
    (asserts! (or (is-authorized-validator checker) (is-eq checker (get planter tree))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get verification-status tree) "verified") ERR-NOT-AUTHORIZED)
    
    ;; Record the checkup
    (map-set tree-checkups
      { tree-id: tree-id, check-date: check-date }
      {
        checker: checker,
        health-status: health-status,
        growth-stage: growth-stage,
        notes: notes,
        photo-hash: photo-hash
      }
    )
    
    ;; Update tree survival status
    (map-set trees
      { tree-id: tree-id }
      (merge tree {
        survival-status: health-status,
        last-check-date: check-date
      })
    )
    
    ;; If tree died, update planter stats
    (if (is-eq health-status "dead")
      (update-planter-stats (get planter tree) u0 (- u0 u1))
      true
    )
    
    (ok true)
  )
)

;; Claim milestone rewards for tree survival
(define-public (claim-milestone-reward (tree-id uint))
  (let (
    (claimer tx-sender)
    (tree (unwrap! (map-get? trees { tree-id: tree-id }) ERR-TREE-NOT-FOUND))
    (species-data (unwrap! (map-get? species-info { species-name: (get species tree) }) ERR-INVALID-SPECIES))
  )
    (asserts! (is-eq claimer (get planter tree)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get verification-status tree) "verified") ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get survival-status tree) "healthy") ERR-TREE-ALREADY-DEAD)
    (asserts! (not (get reward-claimed tree)) ERR-ALREADY-VERIFIED)
    
    ;; Calculate milestone reward based on species and survival
    (let ((milestone-reward (calculate-milestone-reward species-data)))
      ;; Mint reward tokens
      (try! (ft-mint? grow-reward milestone-reward claimer))
      (var-set total-supply (+ (var-get total-supply) milestone-reward))
      
      ;; Mark reward as claimed
      (map-set trees
        { tree-id: tree-id }
        (merge tree { reward-claimed: true })
      )
      
      (ok milestone-reward)
    )
  )
)

;; Read-only functions

;; Get planter information
(define-read-only (get-planter-info (address principal))
  (map-get? planters { address: address })
)

;; Get tree information
(define-read-only (get-tree-info (tree-id uint))
  (map-get? trees { tree-id: tree-id })
)

;; Get species information
(define-read-only (get-species-info (species-name (string-ascii 50)))
  (map-get? species-info { species-name: species-name })
)

;; Get validator information
(define-read-only (get-validator-info (address principal))
  (map-get? validators { address: address })
)

;; Get tree checkup information
(define-read-only (get-tree-checkup (tree-id uint) (check-date uint))
  (map-get? tree-checkups { tree-id: tree-id, check-date: check-date })
)

;; Check if user is registered as planter
(define-read-only (is-planter-registered (address principal))
  (match (map-get? planters { address: address })
    planter-data (get is-active planter-data)
    false
  )
)

;; Check if species is valid and active
(define-read-only (is-valid-species (species-name (string-ascii 50)))
  (match (map-get? species-info { species-name: species-name })
    species-data (get is-active species-data)
    false
  )
)

;; Check if user is authorized validator
(define-read-only (is-authorized-validator (address principal))
  (match (map-get? validators { address: address })
    validator-data (get is-authorized validator-data)
    false
  )
)

;; Get token balance for user
(define-read-only (get-balance (user principal))
  (ft-get-balance grow-reward user)
)

;; Get total token supply
(define-read-only (get-total-supply)
  (var-get total-supply)
)

;; Get next tree ID
(define-read-only (get-next-tree-id)
  (var-get next-tree-id)
)

;; Private functions

;; Update planter statistics
(define-private (update-planter-stats (planter principal) (trees-planted-delta uint) (trees-alive-delta uint))
  (match (map-get? planters { address: planter })
    planter-data
    (begin
      (map-set planters
        { address: planter }
        {
          total-trees-planted: (+ (get total-trees-planted planter-data) trees-planted-delta),
          total-trees-alive: (+ (get total-trees-alive planter-data) trees-alive-delta),
          reputation-score: (get reputation-score planter-data),
          registration-date: (get registration-date planter-data),
          is-active: (get is-active planter-data)
        }
      )
      true
    )
    false
  )
)

;; Update validator statistics
(define-private (update-validator-stats (validator principal) (success bool))
  (match (map-get? validators { address: validator })
    validator-data
    (begin
      (map-set validators
        { address: validator }
        {
          total-validations: (+ (get total-validations validator-data) u1),
          successful-validations: (if success (+ (get successful-validations validator-data) u1) (get successful-validations validator-data)),
          stake-amount: (get stake-amount validator-data),
          is-authorized: (get is-authorized validator-data),
          reputation: (get reputation validator-data)
        }
      )
      true
    )
    false
  )
)

;; Process initial planting reward
(define-private (process-planting-reward (tree-id uint) (tree { planter: principal, species: (string-ascii 50), latitude: (string-ascii 20), longitude: (string-ascii 20), planting-date: uint, verification-status: (string-ascii 20), verifier: (optional principal), survival-status: (string-ascii 20), last-check-date: uint, reward-claimed: bool, carbon-offset: uint }))
  (let (
    (species-data (unwrap! (map-get? species-info { species-name: (get species tree) }) ERR-INVALID-SPECIES))
    (initial-reward (get base-reward species-data))
  )
    ;; Mint initial reward tokens
    (try! (ft-mint? grow-reward initial-reward (get planter tree)))
    (var-set total-supply (+ (var-get total-supply) initial-reward))
    
    ;; Update planter stats
    (update-planter-stats (get planter tree) u0 u1)
    
    (ok true)
  )
)

;; Calculate milestone reward based on species characteristics
(define-private (calculate-milestone-reward (species-data { base-reward: uint, carbon-per-year: uint, survival-rate: uint, growth-period: uint, is-native: bool, is-active: bool }))
  (let (
    (base (get base-reward species-data))
    (carbon-bonus (* (get carbon-per-year species-data) u2))
    (native-bonus (if (get is-native species-data) u50 u0))
  )
    (+ base carbon-bonus native-bonus)
  )
)


