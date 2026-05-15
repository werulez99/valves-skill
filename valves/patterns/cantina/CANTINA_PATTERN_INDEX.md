# Cantina Pattern Library Index

> **Source**: 279 confirmed HIGH/MEDIUM findings from 16 Cantina competitions
> **Generated**: 2026-05-07
> **Total patterns**: 80
> **Total files**: 13
> **New clusters**: 1 (reward-accounting)
> **Format**: Valves pattern library format (Code Shape + Detection Heuristic + Failure Mode)

---

## Summary

| Cluster | File | Patterns | ID Range | New vs Reinforcing |
|---------|------|----------|----------|-------------------|
| Lending & Liquidation | cantina-lending-liquidation.md | 12 | CANTINA-LEND-001..012 | New IDs (supplements LEND-001..035) |
| Logic Errors | cantina-logic-errors.md | 11 | CANTINA-LOGIC-001..011 | New IDs (supplements LOGIC-001..030) |
| DEX & AMM Logic | cantina-dex-amm-logic.md | 9 | CANTINA-DEX-035..043 | Continues from DEX-034 |
| Vault & Share Accounting | cantina-vault-share-accounting.md | 8 | CANTINA-VAULT-029..036 | Continues from VAULT-028 |
| Reward Accounting (NEW) | cantina-reward-accounting.md | 7 | CANTINA-REWARD-001..007 | **New cluster** |
| Denial of Service | cantina-denial-of-service.md | 7 | CANTINA-DOS-031..037 | Continues from DOS-030 |
| Access Control | cantina-access-control.md | 5 | CANTINA-AC-033..037 | Continues from AC-032 |
| Arithmetic & Precision | cantina-arithmetic-precision.md | 5 | CANTINA-ARITH-029..033 | Continues from ARITH-028 |
| Frontrunning & MEV | cantina-frontrunning-mev.md | 5 | CANTINA-MEV-023..027 | Continues from MEV-022 |
| Oracle Dependency | cantina-oracle-dependency.md | 4 | CANTINA-ORACLE-026..029 | Continues from ORACLE-025 |
| Signature & Auth | cantina-signature-auth.md | 3 | CANTINA-SIG-036..038 | Continues from SIG-035 |
| Reentrancy | cantina-reentrancy.md | 2 | CANTINA-REENTRY-019..020 | Continues from REENTRY-018 |
| Bridge & Cross-Chain | cantina-bridge-cross-chain.md | 2 | CANTINA-BRIDGE-046..047 | Continues from BRIDGE-045 |

---

## Pattern Inventory

### Lending & Liquidation (12)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-LEND-001 | strategy_layer_withdrawal_accounting_mismatch | HIGH |
| CANTINA-LEND-002 | negative_yield_unliquidatable_positions | HIGH |
| CANTINA-LEND-003 | bad_debt_ratio_staleness_and_ordering | HIGH |
| CANTINA-LEND-004 | collateral_hiding_from_bad_debt_liquidation | MEDIUM |
| CANTINA-LEND-005 | stablecoin_depeg_death_spiral | HIGH |
| CANTINA-LEND-006 | utilization_cliff_permanent_brick | HIGH |
| CANTINA-LEND-007 | liquidation_fee_avoidance_via_alternative_exit | MEDIUM |
| CANTINA-LEND-008 | force_repay_token_routing_error | HIGH |
| CANTINA-LEND-009 | depositor_dos_via_accounting_invariant_break | HIGH |
| CANTINA-LEND-010 | grace_period_missing_after_parameter_change | MEDIUM |
| CANTINA-LEND-011 | collateral_wrapper_price_mismatch_on_liquidation | HIGH |
| CANTINA-LEND-012 | insolvent_position_liquidation_revert | HIGH |

### Logic Errors (11)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-LOGIC-001 | wrong_transfer_destination_or_source | HIGH |
| CANTINA-LOGIC-002 | wrong_accumulator_or_tracker_referenced | HIGH |
| CANTINA-LOGIC-003 | fee_unit_or_base_mismatch | HIGH |
| CANTINA-LOGIC-004 | inverted_price_or_threshold_trigger | HIGH |
| CANTINA-LOGIC-005 | inverted_proof_or_eligibility_verification | HIGH |
| CANTINA-LOGIC-006 | stale_accounting_from_missing_sync | HIGH |
| CANTINA-LOGIC-007 | formula_variable_substitution_error | HIGH |
| CANTINA-LOGIC-008 | rounding_direction_in_intermediate_computation | MEDIUM |
| CANTINA-LOGIC-009 | withheld_or_reserved_amount_ignored | HIGH |
| CANTINA-LOGIC-010 | price_type_confusion_in_paired_operations | HIGH |
| CANTINA-LOGIC-011 | leverage_or_loop_iterative_drift | HIGH |

### DEX & AMM Logic (9)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-DEX-035 | swap_fee_parameter_ordering | HIGH |
| CANTINA-DEX-036 | position_transfer_penalty_bypass | HIGH |
| CANTINA-DEX-037 | lp_withdrawal_splitting_arbitrage | HIGH |
| CANTINA-DEX-038 | parameter_update_sandwich | HIGH |
| CANTINA-DEX-039 | donation_attack_on_lp_pricing | HIGH |
| CANTINA-DEX-040 | fee_theft_via_reserve_desync | MEDIUM |
| CANTINA-DEX-041 | quadratic_fee_boundary_error | MEDIUM |
| CANTINA-DEX-042 | stableswap_operation_when_paused | MEDIUM |
| CANTINA-DEX-043 | trading_limit_fee_inclusion | MEDIUM |

### Vault & Share Accounting (8)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-VAULT-029 | inflation_attack_with_residual_exposure | HIGH |
| CANTINA-VAULT-030 | first_deposit_zero_price_initialization | HIGH |
| CANTINA-VAULT-031 | dust_rounding_over_seizure | HIGH |
| CANTINA-VAULT-032 | balance_of_accounting_contamination | MEDIUM |
| CANTINA-VAULT-033 | erc4626_maxdeposit_maxredeem_noncompliance | MEDIUM |
| CANTINA-VAULT-034 | vault_loss_withdrawal_deadlock | MEDIUM |
| CANTINA-VAULT-035 | permissionless_vault_wrapper_hijack | HIGH |
| CANTINA-VAULT-036 | shares_inflation_dos | MEDIUM |

### Reward Accounting — NEW CLUSTER (7)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-REWARD-001 | retroactive_boost_weight_manipulation | HIGH |
| CANTINA-REWARD-002 | emission_to_empty_pool_token_lock | MEDIUM |
| CANTINA-REWARD-003 | slash_propagation_to_future_rewards | HIGH |
| CANTINA-REWARD-004 | reward_rate_manipulation_via_dust_or_timing | MEDIUM |
| CANTINA-REWARD-005 | epoch_timestamp_boundary_errors | MEDIUM |
| CANTINA-REWARD-006 | rewards_stuck_after_state_transition | HIGH |
| CANTINA-REWARD-007 | credit_state_monotonicity_violation | MEDIUM |

### Denial of Service (7)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-DOS-031 | unbounded_array_growth_via_user_action | HIGH |
| CANTINA-DOS-032 | zero_balance_rebalance_revert | HIGH |
| CANTINA-DOS-033 | cooldown_extension_on_new_action | HIGH |
| CANTINA-DOS-034 | hardcoded_bound_blocks_operation | HIGH |
| CANTINA-DOS-035 | accounting_overflow_blocks_operations | HIGH |
| CANTINA-DOS-036 | direct_transfer_inflates_accounting | MEDIUM |
| CANTINA-DOS-037 | removal_or_pause_blocks_dependent_operations | MEDIUM |

### Access Control (5)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-AC-033 | missing_caller_validation_on_sensitive_restake | HIGH |
| CANTINA-AC-034 | forged_from_parameter_drains_tokens | HIGH |
| CANTINA-AC-035 | unvalidated_callback_delegatecall_target | HIGH |
| CANTINA-AC-036 | fee_bypass_through_hook_or_wrapper_path | MEDIUM |
| CANTINA-AC-037 | deposit_cap_bypass_through_alternate_entry | MEDIUM |

### Arithmetic & Precision (5)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-ARITH-029 | rounding_direction_state_corruption | HIGH |
| CANTINA-ARITH-030 | fixed_point_overflow_at_utilization_boundary | HIGH |
| CANTINA-ARITH-031 | rounding_elimination_of_small_fees | MEDIUM |
| CANTINA-ARITH-032 | timestamp_first_action_overcharge | MEDIUM |
| CANTINA-ARITH-033 | precision_loss_in_weighted_calculation | MEDIUM |

### Frontrunning & MEV (5)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-MEV-023 | admin_parameter_change_sandwich | HIGH |
| CANTINA-MEV-024 | reward_start_time_frontrun | HIGH |
| CANTINA-MEV-025 | missing_slippage_protection | HIGH |
| CANTINA-MEV-026 | redemption_sandwich_evades_reduction | MEDIUM |
| CANTINA-MEV-027 | forced_routing_through_adversarial_pool | MEDIUM |

### Oracle Dependency (4)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-ORACLE-026 | decimal_mismatch_in_price_computation | HIGH |
| CANTINA-ORACLE-027 | inconsistent_price_type_selection | MEDIUM |
| CANTINA-ORACLE-028 | missing_staleness_check_on_oracle_price | MEDIUM |
| CANTINA-ORACLE-029 | identical_oracle_calls_defeat_deviation_check | MEDIUM |

### Signature & Auth (3)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-SIG-036 | hook_data_decoding_mismatch | HIGH |
| CANTINA-SIG-037 | merkle_proof_leaf_construction_mismatch | HIGH |
| CANTINA-SIG-038 | permit_nonce_and_validity_edge_cases | MEDIUM |

### Reentrancy (2)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-REENTRY-019 | cross_contract_reentrancy_via_external_swap | HIGH |
| CANTINA-REENTRY-020 | chain_reorg_state_replay | MEDIUM |

### Bridge & Cross-Chain (2)
| ID | Name | Severity |
|----|------|----------|
| CANTINA-BRIDGE-046 | cross_chain_state_proof_asymmetry | MEDIUM |
| CANTINA-BRIDGE-047 | hardcoded_slippage_in_cross_chain_swap | MEDIUM |

---

## Severity Distribution

| Severity | Count | % |
|----------|-------|---|
| HIGH | 48 | 60% |
| MEDIUM | 32 | 40% |

---

## Source Contests

Alchemix, Ammalgam, Aquarius, Avon, DefiApp, infiniFi, Jigsaw, Kuru, Mento, Mighty, Morpho, Mystic, Octant, TermMax, VII (+ others)

---

## Integration Notes

- **Existing clusters**: 12 files extend existing Solodit pattern IDs (continuing from the last ID in each cluster)
- **New cluster**: `reward-accounting` is entirely new — covers reward emission, boost manipulation, slash propagation, epoch boundaries
- **Lending-liquidation patterns**: Use CANTINA-LEND prefix (not extending LEND-NNN) since they're structurally distinct from the Solodit lending patterns
- **Logic-errors patterns**: Use CANTINA-LOGIC prefix since they cover Cantina-specific classes (formula substitution, reservation accounting, leverage drift) not in the Solodit set
- **No flash-loan-attacks file**: Few Cantina findings cleanly mapped to standalone flash loan patterns; flash loan elements are embedded in other patterns (DEX-039 donation attack, MEV-023 sandwich)
- **To integrate into Valves**: Copy files to `~/.valves/patterns/`, update `~/.valves/patterns/PATTERN_INDEX.md` to reference them
