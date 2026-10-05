# Literature review: modular learner models for Engram

**Review date:** 5 October 2026 (Australia/Melbourne). **Status:** research and design recommendations; no learner-model or settings implementation is implied. Numbered citations refer to the linked sources at the end.

## 1. Research question and principal conclusion

Which combination of memory, knowledge, difficulty and semantic models is most defensible for a learner who studies both repeatable flashcards and newly generated problems?

**The literature does not establish a universally optimal combination, or establish that FSRS + knowledge tracing + IRT + a knowledge graph + an LLM produces better delayed learning than FSRS alone.** This is a bounded conclusion from the sources reviewed, not a claim that no such experiment exists. The strongest general evidence supports spaced retrieval; evidence for specific learner models is often retrospective prediction, simulation or measurement validation. These evidence types answer different questions.

**Recommended research direction (synthesis):** retain a pinned FSRS baseline for repeatable recall; investigate controlled variation in retrieval tasks; compare an interpretable time-aware multi-skill model such as DAS3H with simple knowledge-tracing baselines; introduce difficulty calibration only where the item bank supports it. Evaluate a joint model later, after the simpler components have earned their place. A modular system is valuable because it makes these comparisons possible, not because every module must be active.

“Optimal” should mean better performance on a specified delayed assessment at a specified time and cost budget. It could instead mean fewer reviews at equivalent retention, better transfer, better calibration, or more accurate diagnosis. These objectives can select different policies. A prediction model estimates what will happen; a teaching policy chooses what to do; an outcome experiment tests whether that choice helps.

## 2. Scope, methods and evidence appraisal

This is a **targeted narrative literature review**, not a registered systematic review or a new meta-analysis. The supplied ChatGPT handover was treated as search context. Its instructions were not followed, and its numerical and novelty claims were checked against primary publications or author-maintained materials.

Searches covered: spacing and retrieval; personalized review and FSRS; BKT/PFA/DAS3H and deep knowledge tracing; IRT and cognitive diagnosis; transfer, interleaving and semantic structure; automatic question generation; and recent integrated systems. Searches used titles, author names and combinations of these concepts. Primary papers, conference proceedings, author/institution repositories and official algorithm documentation were preferred. Foundational papers were retained even when old; newer evidence was sought through the review date. No exhaustive database coverage, pooled reanalysis, duplicate screening or formal risk-of-bias scoring was performed.

Figures below are reported results, with their comparator and endpoint wherever verified. Missing confidence intervals or sample counts are left missing rather than reconstructed. Abstract-only evidence is labeled; inaccessible full texts limit appraisal. Benchmark tables from different datasets, preprocessing pipelines and splits must not be treated as a single leaderboard. Open-source results describe the accessed version and can change.

### Evidence labels used here

| Label | What it means in this review | What it does not mean |
|---|---|---|
| Strong for a general learning principle | Quantitative synthesis of many human experiments | Every implementation or subject will benefit equally |
| Moderate for a particular intervention | Relevant controlled human study, with limits in population, comparator or endpoint | The exact Engram combination has been validated |
| Moderate for prediction/measurement | Real learner data, meaningful comparisons or an established measurement framework | A causal gain in retention or transfer |
| Preliminary | Simulation, preprint, small/domain-specific evaluation or insufficient independent validation | Ready for a “proven better” product claim |
| Unestablished for the proposed combination | No direct supporting comparison identified here | The combination cannot work |

These are editorial judgments, not GRADE ratings. Evidence strength is always attached to a claim and an outcome, not to an algorithm name alone.

## 3. What the current app models

Repository inspection at `d1783b8` found a card-level `FSRSScheduler` identified as `fsrs-6`, wrapping `swift-fsrs-4fbaf201`. It uses `FSRSDefaults.defaultWv6`; the adapter does not fit personalized parameters from the supplied review history. Settings constrain desired retention to 0.70–0.99, use short-term scheduling and fixed learning/relearning steps, and disable fuzz. Consequently, evidence about an optimized FSRS configuration is not automatically evidence about the shipped default-weight configuration.

The app already defines `Scheduler` and an optional `MemoryEstimating` capability, stores versioned scheduling state, and replays reviews with correction events. Research events include estimated recall, rating, question type, grading method, modality and duration. Those inspected fields do not provide a complete concept-level Q-matrix, calibrated item bank or experimental-assignment record.

Local evidence: [scheduler adapter](/Users/akshatporwal/Documents/projects/Memory/Sources/SchedulingAdapters/FSRSScheduler.swift), [contracts](/Users/akshatporwal/Documents/projects/Memory/Sources/LearningCore/Contracts.swift), [research event](/Users/akshatporwal/Documents/projects/Memory/Sources/LearningCore/ResearchEvent.swift), [review reconciliation](/Users/akshatporwal/Documents/projects/Memory/Sources/LearningCore/ReviewReconciliation.swift). These are code observations, not literature claims. No build or simulator run is needed for this document.

## 4. Distinguish the quantities being estimated

| Component | Useful question | Typical evidence | Boundary |
|---|---|---|---|
| Memory / scheduling | Will this learner retrieve this item after this delay? | Repeated item responses, elapsed time, review history | Card recall does not establish flexible application |
| Knowledge tracing (KT) | How does performance on a skill evolve with practice? | Chronological responses mapped to skills | “Mastery” is a model-defined latent estimate |
| IRT / multidimensional IRT | How does task difficulty relate to learner proficiency? | Responses to linked, calibrated items | A score requires an identified scale and appropriate model fit |
| Cognitive diagnosis (CDM) | Which required attributes are likely present or missing? | Diagnostic items and a validated Q-matrix | Wrong skill labels can produce misleading diagnoses |
| Semantic / prerequisite structure | Which tasks share skills, contexts or prerequisites? | Expert maps, task analysis, text features, learned relations | Text similarity is not proof of skill equivalence or transfer |
| Question-selection policy | Which task should be presented next? | Predictions, goals, time cost, coverage and uncertainty | Most accurate prediction need not yield best teaching |
| Generation and grading | Can a valid question and reliable assessment be produced? | Source material, rubrics, human audits, empirical responses | An LLM is not a calibrated learner model |

These are useful interface boundaries, not scientifically independent traits. KT can include forgetting and item difficulty; IRT can be dynamic; joint models can combine structure and time. Do not force overlapping models to pretend they estimate disjoint realities. [9–19, 23–25]

## 5. Memory, retrieval and scheduling

### 5.1 General principles are better established than specific algorithms

The spacing and retrieval literatures support repeated, separated retrieval as a foundation. Their pooled effects are not estimates of the benefit of FSRS over another spaced scheduler. The important comparison is often spaced versus massed practice, or retrieval versus restudy; Engram's baseline already incorporates both principles. [1–2]

Cepeda et al. synthesized **839 assessments from 317 experiments in 184 articles** on verbal recall. The best spacing depended on the final retention interval. Rowland's retrieval-versus-restudy meta-analysis synthesized **159 effect sizes from 61 studies**, with **Hedges' g=.50, 95% CI [.42, .58]**. This is a standardized difference, not a 50% improvement. [1–2]

### 5.2 HLR and personalized review

Half-Life Regression (HLR) models recall as a function of time and a learned memory half-life, with history and linguistic features. Its language-specific evaluation is useful evidence that personalization can improve forecasting; its figures should not be transferred to arbitrary problem solving or a different retention endpoint. [4]

Settles and Meeder evaluated **12.9 million student-word session traces**, with the first 90% for training and the final 10% for testing. Recall-rate MAE was **.128 for HLR**, **.235 for Leitner**, **.211 for logistic regression**, and **.175 for a constant baseline**. HLR's AUC was **.538**, versus Leitner's **.542**: better probability error did not imply better ranking. Deployment experiments measured engagement rather than delayed learning, and linguistic features raised generalization concerns. [4]

Personalized review has also been tested in human classrooms and large learning apps. Those interventions are more directly relevant to learning benefit than a scheduler prediction leaderboard, but neither establishes that all personalized algorithms are equivalent. [3, 7]

Lindsey et al. studied **179 middle-school Spanish learners over one semester**, comparing personalized DASH, generic spaced and massed review with equal review-trial counts. On an exam **28 days after the semester**, reported gains were **16.5% versus massed review (d=1.42)** and **10.0% versus generic spaced review (d=.88)**, both **p<.001**. These are the authors' reported percentage gains, not relabeled percentage-point differences. The design and population constrain generalization, and neither comparator was FSRS. [3]

### 5.3 FSRS: useful baseline, bounded evidence

FSRS uses difficulty, stability and retrievability to model repeated recall. The official algorithm documentation traces it to the DHP/DSR family. Version-specific formulas and fitted parameters matter. [6]

The accessed official SRS benchmark uses data from **10,000 Anki users, approximately 727 million reviews**. Its evaluation excluding same-day reviews contains **349,923,850 reviews**. Selected results below are means with **99% confidence intervals**, not participant learning effects. [5]

| Model / configuration | Log loss ↓ | RMSE in bins ↓ | AUC ↑ |
|---|---:|---:|---:|
| FSRS-6 | 0.3460 ± 0.0042 | 0.0653 ± 0.0011 | 0.7034 ± 0.0023 |
| FSRS-7, recency configuration | 0.3370 ± 0.0042 | 0.0593 ± 0.0010 | 0.7220 ± 0.0021 |
| Moving average | 0.3369 ± 0.0042 | 0.05915 ± 0.00082 | 0.7001 ± 0.0025 |

Most models use time-series splits; the repository notes a different training/evaluation arrangement for RWKV, so its headline ranking is not a fully matched comparison. These are logged responses under existing study behavior, not randomized outcomes under new scheduling policies. Close moving-average results reinforce checking metrics and baselines rather than claiming universal FSRS superiority. [5]

**Design inference:** retain Engram's exact FSRS-6 configuration as the reproducible control. Evaluate parameter fitting and version changes as separate treatments. A “newer scheduler” change and “new learner model” change should not be bundled if the experiment aims to attribute a benefit.

### 5.4 Optimal-control scheduling

MEMORIZE derives schedules under specified memory and review-cost assumptions; its 2019 evaluation includes a Duolingo natural experiment. Mathematical optimality is conditional on the model and objective, and observational agreement with a policy is not random assignment. [8]

The 2021 SELECT trial randomized approximately **50,700 consenting adult learners** in a German driving-theory app. The final publication reports **about 69% longer memory duration after controlling for study length and frequency**. The endpoint is estimated memory duration/half-life, not a 69-percentage-point increase in examination accuracy. The earlier preprint's approximately 67% figure should not replace the final article. Different comparisons and engagement outcomes vary; follow-up usage and dropout require attention. This is important human intervention evidence for data-driven session selection, but the comparator was heuristic sequencing, not Engram's FSRS or a validated transfer curriculum. [7]

**Assessment:** strong support for spaced retrieval in general; moderate, context-specific support for personalized practice policies; substantial retrospective evidence for FSRS recall forecasting; unestablished superiority of an FSRS-based modular stack on Engram learning outcomes.

## 6. Knowledge tracing and multi-skill learning

### 6.1 Interpretable baselines: BKT and PFA

Bayesian Knowledge Tracing (BKT) represents each skill as learned/unlearned, with parameters for initial knowledge, learning, guessing and slipping. Classical BKT does not include forgetting. The probability of being in the learned state is not the same as probability of a correct response. It is a useful interpretable baseline, particularly with curated skills, but a binary state need not capture partial understanding or flexible transfer. [9]

Performance Factors Analysis (PFA) uses skill-specific prior successes and failures to predict performance and accommodates multi-skill items. Plain cumulative counts do not encode actual elapsed-time forgetting. The source PDF was identified on the authors' institutional site, but its full text could not be fetched here; no exact performance advantage is asserted. [10]

An expanded BKT captured contextual and learner regularities and matched DKT in the experiments of Khajah et al. This does not make BKT universally competitive with every modern model, but demonstrates why a thoughtfully specified simple baseline matters. [13]

### 6.2 DAS3H: a particularly relevant candidate

DAS3H combines learner, item and skill effects with skill-specific practice history across **1-hour, 1-day, 7-day, 30-day and unbounded windows**. It directly addresses elapsed time and multi-skill practice. Five-fold student-level cross-validation produced the following AUCs (mean ± fold standard deviation; selected configurations from Tables 2–3). [11]

| Dataset | DAS3H | DASH | PFA | IRT |
|---|---:|---:|---:|---:|
| Algebra 2005–2006 | .826 ± .003, d=0 | .775 ± .005, d=5 | .744 ± .004, d=0 | .771 ± .007 |
| ASSISTments 2012–2013 | .744 ± .002, d=5 | .703 ± .002, d=0 | .669 ± .002, d=5 | .702 ± .001 |

Here `d` is embedding dimension. The original study did not compare DKT. The simple no-embedding DAS3H configuration won on Algebra. These results support testing a time-aware multi-skill predictor, not a claim that its scheduler improves retention by the AUC difference. [11]

**Design inference:** DAS3H is a promising first concept-level challenger, especially where many tasks reuse skills but individual generated questions rarely recur. Use it initially for shadow prediction or practice selection, with explicit ownership of any scheduling decisions that overlap FSRS.

### 6.3 Deep and attention-based models

DKT uses recurrent neural networks to summarize response sequences. Its historical results helped motivate deep KT; they do not establish a contemporary universal advantage or a causal learning improvement. [12]

AKT uses context-sensitive monotonic attention and Rasch-inspired embeddings. Contextual sequence distance should not automatically be interpreted as elapsed calendar time; Rasch-inspired representations are not automatically a calibrated assessment scale. [14]

The pyKT study used **20% held-out students**, five-fold training/validation on the remaining students, maximum training sequence length 200, and question-level aggregation of skill predictions. Table 2 reports: [15]

| Dataset | DKT AUC | AKT AUC | Absolute difference |
|---|---:|---:|---:|
| ASSISTments2009 | .7541 | .7853 | .0312 |
| Algebra2005 | .8149 | .8306 | .0157 |
| Bridge2006 | .8015 | .8208 | .0193 |
| NIPS34 | .7689 | .8033 | .0344 |

Its leakage demonstration inflated DKT skill-level AUC from **.7419 to .8262** on ASSISTments2009 and **.8146 to .9218** on Algebra. Expanding one question into skill records can expose its response before every prediction is made. Predict all required skills before updating from that answer. None of these AUCs measure teaching efficacy. [15]

simpleKT illustrates the value of a simpler neural comparator: NIPS34 AUC was **.8035** versus AKT's **.8033**, while AKT won on six of seven datasets in that study. Small differences can be outweighed by calibration, cost and operational simplicity. [16]

Recent leakage work continues to identify problems in multi-skill training and evaluation; preventing leakage only in the final test procedure is insufficient. [35]

**Assessment:** moderate evidence that several neural models improve next-response prediction on established datasets; insufficient direct evidence that choosing the highest AUC improves delayed retention or transfer in this application. Train/test separation must include question families and concepts where the intended deployment requires generalization to new material.

## 7. Ability, difficulty and diagnostic assessment

### 7.1 IRT and dynamic IRT

In a basic logistic IRT model, response probability depends on learner proficiency relative to item difficulty; richer models add discrimination, guessing, multiple dimensions or partial credit. The scale must be identified and its interpretation supported by item design and model fit. IRT is an established measurement framework, not a guarantee that adaptive instruction benefits learning. [23]

Dynamic IRT predates LLMs and explicitly models ability changing over repeated observations. Wang et al. use a state-space formulation, account for dependencies and uncertain difficulty, and demonstrate online/retrospective inference on reading-test data. This is a more appropriate conceptual alternative to treating a learner's ability as fixed throughout a course. [24]

**Design inference:** begin with a Rasch/1PL or hierarchical item-family model on a curated, linked bank. Move to 2PL, multidimensional or partial-credit models only if fit and available evidence justify the extra parameters. One uniquely generated question answered by one learner does not independently identify its difficulty, discrimination and that learner's proficiency. Reusable anchor items and pooled item families are therefore especially valuable.

### 7.2 Deep-IRT is integration prior art

Deep-IRT maps memory-network estimates into ability/difficulty terms through an IRT response function. On ASSIST2009, Table 2 reports AUC **81.65 ± .02** for Deep-IRT versus **81.61 ± .06** for DKVMN on a 0–100 scale: **.8165 versus .8161**. The AUC comparison has **p=.2581**. Its 30% sequence holdout and preprocessing differ from pyKT, so those tables cannot be directly ranked. The contribution is an interpretable output form with similar prediction in that comparison, not established superior learning or independent psychological validity of its latent ability. [17]

### 7.3 DINA and G-DINA

DINA is a diagnostic model in which an item requires a conjunction of designated attributes; guessing and slipping permit imperfect responses. It is most plausible for a curated diagnostic assessment with a defensible item-to-attribute Q-matrix. It does not by itself supply elapsed-time scheduling. [18]

G-DINA relaxes interaction restrictions and permits richer attribute-response relationships, at a higher calibration burden. Its foundational paper is **2011**, notwithstanding migrated publisher metadata. [19]

DINA identifiability depends on the structure of the Q-matrix and assessment design. A model can output clean-looking mastery probabilities without the data uniquely identifying them. [34]

**Design inference:** reserve CDMs for domains with explicit attributes and enough diagnostic coverage. Multi-step solutions and rubric dimensions may provide more useful diagnostic evidence than a single final-answer grade, but those dimensions need reliability studies. A Q-matrix generated by an LLM should remain a proposed mapping until checked.

### 7.4 Adaptive difficulty does not establish optimal teaching

A Dutch secondary-school randomized comparison found no average test-score advantage for adaptive over static practice. Static practice benefited higher-ability students by **0.08 standard deviations**; adaptive users received harder tasks, practiced longer and answered fewer correctly. Modest uptake and differences between the environments constrain interpretation, but the result challenges an automatic “adaptive is better” assumption. [32]

The “85% rule” derives approximately **15.87% optimal training error** under specified binary-classification and learning assumptions, demonstrated in artificial and biologically motivated network simulations. It is not a human trial establishing 85% as the universal success target for educational problem solving. [33]

**Design inference:** assessment and instruction need distinct difficulty policies. Items near maximum statistical information can be useful for estimating proficiency; instructional tasks may require scaffolding, feedback and successful retrieval. Treat difficulty bands as tunable experimental policies, not literature-proven universal settings.

## 8. Transfer, variation, interleaving and semantic structure

### 8.1 Retrieval can transfer, but the task matters

Pan and Rickard's meta-analysis covers **192 transfer effect sizes, 122 experiments, 67 articles and 10,382 participants**. Retrieval versus nontesting reexposure produced **d=.40, 95% CI [.31, .50]**. The result supports transfer from retrieval under studied conditions, with meaningful moderators. It does not measure the incremental benefit of an AI variation policy over fixed-card FSRS. [20]

Butler et al. tested genuinely different applications of concepts across **four experiments**, followed by a novel application test **two days later**. Pooled retrieval-condition performance was **.66 for variable examples versus .53 for the same example**, based on **793 versus 780 concept-within-participant observations**, not independent participants. Experiment 3 had **48 participants** and a variability effect **F(1,46)=6.14, p=.017, η²=.12**. This supports variation in application, with a short follow-up and narrow tasks; changing wording alone is not equivalent. [21]

### 8.2 Interleaving is a separate intervention

Rohrer et al.'s preregistered classroom cluster trial involved **787 grade-7 students in 54 classes**, comparing mostly interleaved with mostly blocked mathematics practice over four months. An unannounced test **one month later** yielded **61% versus 38%, d=.83**. The same problem types appeared in different orders. This supports practice that requires learners to select a strategy, but it is not a comparison against personalized FSRS and does not isolate within-concept semantic variation. [22]

**Design inference:** record whether a task changes surface context, representation, required inference, strategy selection or skill combination. A paraphrase, a new worked example, an interleaved problem and a far-transfer task should not all receive one “novel” label. Measure transfer with withheld tasks whose solution and assessment rubric were not used to train or tune the policy.

### 8.3 Graphs and joint models

PSI-KT is important prior art: a hierarchical generative model combining learner traits, temporal knowledge dynamics and prerequisite structure. The ICLR 2024 paper evaluates prediction on **three platform datasets**, including multi-step and continual-learning settings. It supports the feasibility of a joint structured model, not causal proof that inferred graph edges represent prerequisites or that its teaching policy improves learning. [25]

The LECTOR preprint reports **100 simulated learners, 100 days and 25 concepts per learner**. Table 1 gives success rates **.902 for LECTOR, .896 for FSRS and .884 for SSP-MMC**. Its FSRS difference is **0.6 percentage points**. Reported review attempts are **50,706 versus 151,848 versus 42,743**, respectively. These are simulator quantities, not human study outcomes. The abstract identifies SSP-MMC as the best baseline even though the results show higher FSRS success; algorithm comparability and simulator assumptions need scrutiny. Treat it as semantic-scheduling prior art, not validated superiority in learners. [30]

**Design inference:** embeddings can propose related content or detect duplicate questions; use curated mappings before automatically awarding credit to prerequisites or neighbors. A learner can solve an advanced task with a memorized pattern, a hint or compensation from another skill. Graph propagation should increase uncertainty-aware predictions only under a specified model, not silently manufacture direct evidence of mastery.

## 9. Generated questions, grading and AI tutoring

### 9.1 Generation quality and difficulty calibration

Law et al. compared **100 GPT-4o MCQs with 100 human MCQs**, tested by **24 emergency-medicine doctors**. Proportion correct was **.78±.22 versus .69±.23 (p<.01)**; discrimination was **.22±.23 versus .26±.26**. Factual errors were **6% versus 4%**, irrelevant items **6% versus 0%**, and inappropriate difficulty **14% versus 1%**. Reviewed creation took **24.5 versus 96 person-hours**. AI items were easier and included fewer application/analysis tasks. This small, domain-specific comparison supports reviewed generation and empirical validation, not instant calibrated question production. [26]

A 2026 preprint on reading/writing difficulty prediction reports best zero-shot GPT-4.1 **quadratic weighted κ=.578**, versus **.625 for ConvBERT**. Models struggled with hard items; semantic embeddings alone did not cleanly separate difficulty. Only the abstract was inspected here, and source metadata is inconsistent about the submission date, so this is preliminary supplementary evidence. It does not quantify the accuracy of every model or subject. [27]

**Design inference:** an “easy/medium/hard” generation prompt is a design target, not a calibrated difficulty estimate. Track template/item family, sources, answer key, rubric, concept map, requested difficulty, observed difficulty, revisions and generator version. Curated examples can precede LLM generation in an experiment, isolating whether variation helps before introducing generation errors.

### 9.2 Grading is a measurement layer

Henkel et al.'s accessible manuscript examines **1,710 short responses to 12 science/history questions**, marked by **38 teachers**. Few-shot GPT-4 agreement was **κ=.70**, versus human–human **κ=.75**. It focused on ambiguous answers after excluding null/exact exemplars. Agreement on a limited binary grading task does not validate rich concept-level inference. [36]

A contrasting study, published in 2026 after a 2025 preprint, examined **557 postgraduate medical answers from 215 students** on three ventilation cases. GPT-4o versus human grading had mean bias **−1.34 points out of 10**, **ICC1=.086**, and **κ=−.0786**. Internal consistency across AI runs did not imply agreement with humans. Different tasks and metrics prevent pooling these results with the prior study. [37]

**Design inference:** validate grading by question type and domain against adjudicated human rubrics. Distinguish incorrect, incomplete, hinted, ambiguous, ungraded and disputed responses. Do not convert every partial-credit value into an FSRS rating or skill success without a prespecified measurement rule. Corrections should replay affected estimates; confidence from the grader is not an empirically validated reliability score.

### 9.3 Tutor benefits do not validate a learner-model stack

Kestin et al.'s randomized crossover study included **194 Harvard physics students** over two lessons. Median post-test scores were **4.5 in AI observations versus 3.5 in classroom observations**; the reported standardized regression coefficient was **.63**. Median AI time was **49 minutes**, compared with an approximately 60-minute class. This supports a carefully designed pedagogical tutor on immediate learning, with limits in population, duration and setting. It does not establish long-term retention or FSRS integration benefits. [28]

Bastani et al.'s field experiment with **nearly 1,000 high-school learners** found assisted-practice relative improvements of **48% for GPT Base** and **127% for guarded GPT Tutor**. Subsequent unaided performance was **17% lower for GPT Base** than control; safeguards largely mitigated harm. These are relative changes, not percentage points. Assistance can improve task completion while weakening independent performance, so research assessments must remove the tutor. [29]

Onco-Shikshak's 2026 V7 design preprint integrates **FSRS v4, IRT, ACT-R-inspired activation, scaffolding, metacognition and AI workflows**. It describes **18 cases and six cancer types**, and explicitly says a learner randomized trial is planned. This is architecture prior art, not evidence of educational superiority. The older author-hosted v0 describes SM-2 and should not be substituted for the newer paper. Integration or generation alone is therefore an unsafe novelty claim. [31]

### 9.4 Laya as a local automatic-marking candidate

**Assessment added 5 October 2026:** Laya is a plausible experimental measurement component, separate from the memory/skill model. No direct validation of Laya on student-answer grading was identified in the sources inspected.

The official model card describes a **421M-parameter English encoder**, structured choice/ordinal-score/boolean outputs, and an approximately **808 MB checkpoint download**. Its reported single-question latency is **39.5 ms for English and 32.8 ms for multilingual on a Tesla T4**. These are not iPhone latency measurements. The English default budget is **512 tokens, with about 320 for the state**, limiting space for question, answer, reference and rubric. Its business-workflow benchmark reports **.362 accuracy for the base English model, .766 after task-specific fine-tuning, and .461 for the majority baseline**. Those results do not validate grading accuracy. [38]

The specialist checkpoint's card warns that it was trained on **four synthetic workflows**, may generalize poorly elsewhere, and requires confidence recalibration on held-out data. Its reproducible fine-tuning example takes **about 4–5 hours on two T4 GPUs**; that is not evidence that a quick educational fine-tune matches a stronger grader. [40]

The repository links an Apple-silicon runtime, but this review did not verify native iPhone execution or peak memory. Download/weight size is not total inference memory: activations, runtime buffers and other app models also contribute. A structured classifier avoids malformed generated prose, yet can still assign a confidently wrong mark. [39; design inference]

**Proposed evaluation:** retain deterministic checks for exact/numeric answers. Test Laya against the existing grader and adjudicated human labels on short factual responses and explicit rubric dimensions. Hold out whole question families; include paraphrases, negation, contradictions, partial answers, fluent wrong answers and unseen topics. Compare false acceptance, false rejection, ordinal agreement, calibration and the proportion safely auto-marked at a prespecified error tolerance. Measure memory, cold/warm latency and battery behavior on actual target devices before promising mobile performance. Use a separately validated fallback for ambiguous or complex reasoning; never multiply rubric-check probabilities as independent evidence. Run in shadow mode before it changes scheduling or mastery estimates.

**Research priority:** promising for local, low-latency marking; preliminary for educational accuracy and mobile deployment. Include base and education-fine-tuned variants as grading ablations, while keeping question selection and learner models fixed.

## 10. Comparing candidate combinations

The table is a research prioritization judgment, not a literature-derived performance ranking. “Moderate prediction evidence” does not upgrade an untested combination to “moderate learning evidence.”

| Candidate | What it offers | Supporting literature | Evidence for the exact combination | Main constraint | Priority |
|---|---|---|---|---|---|
| Pinned FSRS-6, fixed recall tasks | Reproducible item-retention control | Spacing/retrieval; official recall benchmark [1–6] | Engram learning benefit not directly measured | Defaults differ from fitted configurations; no transfer estimate | Essential baseline |
| FSRS + curated varied applications | Retention scheduling plus broader retrieval contexts | Human variation and transfer studies [20–21] | Unestablished versus FSRS alone | Novel tasks need separate evidence rules; preserve dose | First learning-outcome experiment |
| FSRS + interpretable BKT/PFA | Recall plus skill-performance tracking | Classic and extended baselines [9–10, 13] | Unestablished | Forgetting, item effects and skill labels need explicit treatment | Low-complexity comparator |
| FSRS + DAS3H | Item memory plus time-aware multi-skill predictions | DAS3H offline evaluations [11] | Unestablished | Overlapping memory predictions; skill mapping and training | First model challenger |
| FSRS + calibrated IRT difficulty | Recall timing plus linked difficulty/proficiency estimates | Measurement/dynamic modeling [23–24] | Unestablished | Shared anchors and item calibration; instructional policy separate | After bank validation |
| FSRS + DINA/G-DINA diagnostics | Recall plus attribute-level diagnostic profile | CDM theory and identifiability [18–19, 34] | Unestablished | Curated Q-matrix and diagnostic coverage | Domain-specific track |
| FSRS + AKT/simpleKT or Deep-IRT | Flexible response prediction | Reproducible deep-KT comparisons [14–17] | Unestablished | Data, calibration, portability and explainability | Offline challenger first |
| Joint graph/time model, e.g. PSI-KT | Unified temporal/structural inference | Joint model evaluation [25] | Unestablished in Engram | Learned relations and model fit need validation | Later research track |
| Full FSRS + KT + IRT + graph + LLM | Broad adaptive teaching loop | Components and integration prior art [11, 17, 25–31] | Unestablished | Attribution, identifiability, grading noise and cost | Defer until ablations justify it |

### Proposed settings summary

This is copy/design guidance for a future settings screen; no screen has been implemented. Prefer understandable presets over unrestricted combinations that cannot be validated together.

| User-facing option | Plain-language summary | Literature strength shown | Availability rule |
|---|---|---|---|
| Recall practice | Schedules repeatable questions using your review history | Strong evidence for spaced retrieval; scheduler evidence is prediction-based | Default baseline |
| Varied application practice | Adds different examples of the concepts you study | Controlled studies support varied applications; this combination remains experimental | Reviewed task families available |
| Skill-aware practice | Uses performance across related questions to estimate skills | Moderate evidence for predicting responses; learning gains still under study | Sufficient skill-tagged data |
| Calibrated difficulty | Selects from questions with measured difficulty | Established assessment framework; adaptive learning benefit depends on policy | Linked item bank available |
| Diagnostic assessment | Estimates specific strengths and gaps | Established model family; validity depends on assessment design | Validated diagnostic domain |
| Research models | Tests newer neural or graph models | Prediction/simulation evidence; outcomes not yet established | Explicit research configuration |

Show the **goal, model version, data readiness, uncertainty, evidence type, expected workload and whether AI is required**. Avoid “best model,” “proven mastery” or a universal percentage learning improvement. Give evidence details on demand, including population, comparator and follow-up. If the user's library lacks calibrated items or skill coverage, say “not enough evidence yet” rather than displaying precise mastery scores.

Self-selected presets are useful product choices, but comparing their users observationally will be confounded by motivation, subject and prior proficiency. Product choice and randomized research assignment should be represented separately.

## 11. Handling shared evidence without double counting

The handover identifies a real risk but overstates it if interpreted as “one answer may update only one model.” **Several models may legitimately consume the same observation.** The problem occurs when their derived estimates are fused as if they were independent evidence, or repeated processing counts one event more than once.

**Proposed design, not an empirically validated architecture:**

1. Store one immutable attempt identifier, item/family version, timestamp, skill map, assistance status and assessment version.
2. Produce all pre-response predictions before any component sees the response.
3. Record the observed answer and measurement uncertainty separately from model estimates.
4. Let shadow models update once each from the event, retaining distinct outputs and uncertainty.
5. Give one specified policy responsibility for the actual selection/scheduling decision. Do not average recall, mastery and ability percentages.
6. For a joint model, use one response likelihood conditioned on its latent states. Do not multiply FSRS, KT and IRT predictions as independent observations of the same answer.
7. Use corrections to invalidate/replay derived updates; preserve original predictions for honest retrospective evaluation.

A correct unassisted repeated recall answer can inform item memory. A novel application answer can inform skill performance, conditional on item demands. Hinted completion, source lookup, transcription uncertainty and unverified grades require different rules. Evidence about a multi-skill final answer is not proof that every component skill has been mastered. If FSRS is extended from cards to concepts, that extension becomes a new modeling hypothesis to validate.

## 12. Research program to identify the best combination

The following is a proposed study program. Its timings, thresholds and analysis choices are suggestions requiring domain-specific piloting, not values established by the literature.

### Stage A: measurement and offline validation

Create a small curated bank with explicit concepts, matched task families, rubrics and reusable anchors. Check question accuracy, mapping agreement and grading reliability before judging a learner model. Evaluate defaults versus fitted parameters separately.

Compare simple empirical baselines, pinned FSRS, BKT/PFA and DAS3H. Add AKT/simpleKT only once enough representative history exists. Use chronological evaluation; separately test new learners, new items/families and new concepts. Group multi-skill records from the same attempt. Train feature extraction, calibration and hyperparameter selection without future/test evidence. Log predictions before the response is graded. The leakage demonstrations make this separation essential. [15, 35]

Report log loss, Brier score, calibration plots/slope/intercept, AUC, uncertainty coverage where defined, and computational cost. Stratify by domain, delay, task type, assistance, input modality and history length. Report cluster-aware uncertainty rather than treating every review as an independent participant. A model advancing to the next stage should show a useful improvement under the deployment split, not merely a significant result on millions of correlated observations.

### Stage B: isolate task variation

Compare **A: fixed retrieval + pinned FSRS** with **B: curated varied retrieval + the same retention control and matched exposure budget**. Prespecify how application attempts affect recall scheduling; keep grading and feedback comparable. If isolating variation proves impossible without changing the scheduling policy, describe the experiment as a package comparison.

Primary outcome: unassisted delayed performance on withheld tasks. Suggested follow-ups are 7 and 30 days, adjusted to the educational goal. Measure fixed-item recall and new-example application separately. Include a prespecified farther-transfer outcome where a credible task can be designed. Avoid using AI-generated grading as the only outcome measure when the intervention itself changes AI question generation.

### Stage C: test adaptation rather than merely estimation

Compare B with **C: varied retrieval selected using an interpretable skill model**. Then compare C with **D: skill-aware selection plus empirically calibrated difficulty**. Keep sources, tutor availability and grading constant where possible. A factorial design can test interactions if adequately powered; otherwise a smaller staged design will be easier to interpret.

For efficiency, compare retained knowledge at a fixed study-time budget, or study time/reviews needed to reach a prespecified retention target. Count feedback, hints, retries and grading time. If reviews are reduced, establish an acceptable retention/transfer noninferiority margin before data collection; fewer reviews alone is not success.

### Stage D: joint and neural policies

Only after C or D improves outcomes should a full joint/graph or neural policy be compared with the best simpler policy. Include ablations that remove time awareness, difficulty, graph propagation and novelty selection where their effects remain unresolved. A larger stack beating basic FSRS does not show which component caused the gain.

### Design and analysis safeguards

Within-person assignment of matched concept sets can control stable learner differences, but related concepts may contaminate each other through transfer. Use sufficiently separated concept clusters, counterbalancing and participant/item effects; consider learner/class-level assignment when tutor behavior or prerequisite learning crosses conditions. Immediate crossover is poor protection when learning carries over permanently.

Do not choose a sample size from an unrelated paper's standardized effect. Estimate plausible item/learner/class variance, repeated-measure correlation, minimum educationally meaningful difference, allocation and dropout; then simulate power for the actual mixed or clustered design. Preregister a primary endpoint, multiplicity strategy, intention-to-treat analysis and sensitivity analyses for missing follow-ups. Retain assignment and exposure records even for learners who stop practicing.

Keep learning outcomes separate from engagement. Delayed recall, transfer, calibration and learning per minute are research outcomes; session completion, return rate, latency, AI cost and grading disputes are product outcomes. Report both when relevant, without replacing one with the other.

## 13. Remaining gaps and decision

The unresolved questions are substantive: whether concept-level evidence generalizes across question families; whether generation reliably targets difficulty; whether noisy grades distort inferred skills; whether semantic relations predict transfer; and whether model-informed selection improves unassisted delayed performance over a strong spaced-retrieval baseline.

This review supports **modularity for comparison, reproducibility and uncertainty**, with a restrained initial set of candidates. It does not support giving every user unrestricted algorithm combinations or describing a particular stack as optimal. The highest-priority experiment is controlled variation with the current FSRS baseline; the highest-priority additional predictor is an interpretable time-aware multi-skill model. Difficulty and diagnostic models become more useful as the item bank and measurement design mature.

## 14. Numbered sources

Links point to primary publications, author/institution manuscripts or official technical materials. Some full-text fetches were unavailable; abstract-only or limited-access use is noted in the relevant discussion. “Preprint” and “benchmark” are not peer-reviewed learning trials.

1. Cepeda et al. (2006). *Distributed practice in verbal recall tasks: A review and quantitative synthesis.* [Publication record](https://pubmed.ncbi.nlm.nih.gov/16719566/); [full text](https://www.escholarship.org/content/qt3rr6q10c/qt3rr6q10c.pdf).
2. Rowland (2014). *The effect of testing versus restudy on retention: A meta-analytic review of the testing effect.* [Publication record](https://pubmed.ncbi.nlm.nih.gov/25150680/); [DOI](https://doi.org/10.1037/a0037559).
3. Lindsey et al. (2014). *Improving Students' Long-Term Knowledge Retention Through Personalized Review.* [Author-hosted published PDF](https://home.cs.colorado.edu/~mozer/Research/Selected%20Publications/reprints/LindseyShroyerPashlerMozer2014Published.pdf); [DOI](https://doi.org/10.1177/0956797613504302).
4. Settles & Meeder (2016). *A Trainable Spaced Repetition Model for Language Learning.* [ACL paper and PDF](https://aclanthology.org/P16-1174/).
5. Open Spaced Repetition. *SRS benchmark.* [Official repository](https://github.com/open-spaced-repetition/srs-benchmark); [snapshot at review](https://github.com/open-spaced-repetition/srs-benchmark/tree/bd9110f791e5b37282c55a9aa8db35f68f0c4aa2). Live developer-maintained benchmark; accessed 5 October 2026.
6. Open Spaced Repetition. *The Algorithm.* [Official FSRS documentation](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm). Technical documentation; accessed 5 October 2026.
7. Upadhyay et al. (2021). *Large-scale randomized experiments reveals that machine learning-based instruction helps people memorize more effectively.* [Published article](https://www.nature.com/articles/s41539-021-00105-8); [institution-hosted final PDF](https://pure.mpg.de/pubman/item/item_3658215_2/component/file_3658216/s41539-021-00105-8.pdf).
8. Tabibian et al. (2019). *Enhancing human learning via spaced repetition optimization.* [Published article](https://doi.org/10.1073/pnas.1815156116); [full text](https://pmc.ncbi.nlm.nih.gov/articles/PMC6410796/).
9. Corbett & Anderson (1995). *Knowledge tracing: Modeling the acquisition of procedural knowledge.* [Published article](https://doi.org/10.1007/BF01099821).
10. Pavlik, Cen & Koedinger (2009). *Performance Factors Analysis—A New Alternative to Knowledge Tracing.* [Institution-hosted PDF](https://pact.cs.cmu.edu/pubs/AIED%202009%20final%20Pavlik%20Cen%20Keodinger%20corrected.pdf). Full fetch unavailable during this review.
11. Choffin et al. (2019). *DAS3H: Modeling Student Learning and Forgetting for Optimally Scheduling Distributed Practice of Skills.* [Full text](https://arxiv.org/html/1905.06873); [record](https://arxiv.org/abs/1905.06873). EDM paper.
12. Piech et al. (2015). *Deep Knowledge Tracing.* [NeurIPS paper](https://papers.nips.cc/paper_files/paper/2015/file/bac9162b47c56fc8a4d2a519803d51b3-Paper.pdf).
13. Khajah, Lindsey & Mozer (2016). *How deep is knowledge tracing?* [Author manuscript](https://arxiv.org/abs/1604.02416).
14. Ghosh, Heffernan & Lan (2020). *Context-Aware Attentive Knowledge Tracing.* [Author manuscript](https://arxiv.org/abs/2007.12324); [author-hosted KDD PDF](https://people.umass.edu/~andrewlan/papers/20kdd-akt.pdf).
15. Liu et al. (2022). *pyKT: A Python Library to Benchmark Deep Learning based Knowledge Tracing Models.* [NeurIPS paper](https://papers.neurips.cc/paper_files/paper/2022/file/75ca2b23d9794f02a92449af65a57556-Paper-Datasets_and_Benchmarks.pdf).
16. Liu et al. (2023). *simpleKT: A Simple But Tough-to-Beat Baseline for Knowledge Tracing.* [Full text](https://arxiv.org/html/2302.06881).
17. Yeung (2019). *Deep-IRT: Make Deep Learning Based Knowledge Tracing Explainable Using Item Response Theory.* [Primary manuscript](https://arxiv.org/pdf/1904.11738).
18. Junker & Sijtsma (2001). *Cognitive Assessment Models with Few Assumptions, and Connections with Nonparametric Item Response Theory.* [Institution-hosted paper](https://research.tilburguniversity.edu/files/437495/cognitive.pdf).
19. de la Torre (2011). *The Generalized DINA Model Framework.* [Published article](https://doi.org/10.1007/s11336-011-9207-7).
20. Pan & Rickard (2018). *Transfer of Test-Enhanced Learning: Meta-Analytic Review and Synthesis.* [Published article](https://doi.org/10.1037/bul0000151); [paper PDF](https://pdf.retrievalpractice.org/transfer/Pan_Rickard_2018.pdf).
21. Butler, Black-Maier, Raley & Marsh (2017). *Retrieving and Applying Knowledge to Different Examples Promotes Transfer of Learning.* [Published article](https://doi.org/10.1037/xap0000142).
22. Rohrer, Dedrick, Hartwig & Cheung (2020; online 2019). *A randomized controlled trial of interleaved mathematics practice.* [Published article](https://doi.org/10.1037/edu0000367); [funded study details](https://ies.ed.gov/use-work/awards/efficacy-study-interleaved-mathematics-practice).
23. Chen, Li, Liu & Ying (2021 manuscript). *Item Response Theory—A Statistical Framework for Educational and Psychological Measurement.* [Primary authors' review](https://arxiv.org/abs/2108.08604).
24. Wang, Berger & Burdick (2013). *Bayesian analysis of dynamic item response models in educational testing.* [Published article](https://doi.org/10.1214/12-AOAS608); [author manuscript](https://arxiv.org/abs/1304.4441).
25. Zhou et al. (2024). *Predictive, scalable and interpretable knowledge tracing on structured domains.* [ICLR paper](https://proceedings.iclr.cc/paper_files/paper/2024/file/99238c9d7ad8c6d138dc417fd8e3740c-Paper-Conference.pdf); [author manuscript](https://arxiv.org/abs/2403.13179).
26. Law et al. (2025). *AI versus human-generated multiple-choice questions for medical education: a cohort study in a high-stakes examination.* [Primary published study](https://doi.org/10.1186/s12909-025-06796-6).
27. Wang et al. (2026). *Can LLMs Really Understand Item Difficulty Levels? Implications for Automated Item Generation Using LLMs.* [Preprint](https://arxiv.org/abs/2607.28634). Abstract-only use; date metadata discrepancy.
28. Kestin et al. (2025). *AI tutoring outperforms in-class active learning: an RCT introducing a novel research-based design in an authentic educational setting.* [Primary published trial](https://doi.org/10.1038/s41598-025-97652-6).
29. Bastani et al. (2025). *Generative AI without guardrails can harm learning.* [Published article](https://doi.org/10.1073/pnas.2422633122); [author manuscript](https://hamsabastani.github.io/education_llm.pdf).
30. Zhao (2025). *LECTOR: LLM-Enhanced Concept-based Test-Oriented Repetition for Adaptive Spaced Learning.* [Primary preprint full text](https://arxiv.org/html/2508.03275v1); [record](https://arxiv.org/abs/2508.03275).
31. Makani (2026). Onco-Shikshak V7 design. [Primary medRxiv preprint](https://www.medrxiv.org/content/10.64898/2026.02.23.26346944v1.full).
32. van Klaveren, Vonk & Cornelisz (2017). *The effect of adaptive versus static practicing on student learning—evidence from a randomized field experiment.* [Published article](https://doi.org/10.1016/j.econedurev.2017.04.003); [institution record](https://research.vu.nl/en/publications/the-effect-of-adaptive-versus-static-practicing-on-student-learni/).
33. Wilson et al. (2019). *The Eighty Five Percent Rule for optimal learning.* [Published article](https://doi.org/10.1038/s41467-019-12552-4); [publication record](https://pubmed.ncbi.nlm.nih.gov/31690723/).
34. Gu & Xu (2019). *The Sufficient and Necessary Condition for the Identifiability and Estimability of the DINA Model.* [Published article](https://doi.org/10.1007/s11336-018-9619-8); [author manuscript](https://arxiv.org/abs/1711.03174).
35. Badran & Preisach (2025). *Addressing Label Leakage in Knowledge Tracing Models.* [Primary manuscript](https://arxiv.org/abs/2403.15304); [CSEDU paper](https://doi.org/10.5220/0013275200003932).
36. Henkel et al. (2024). *Can Large Language Models Make the Grade? An Empirical Study Evaluating LLMs Ability to Mark Short Answer Questions in K-12 Education.* [Primary accessible manuscript](https://arxiv.org/abs/2405.02985); [PDF](https://arxiv.org/pdf/2405.02985).
37. Jade & Yartsev (2026). *ChatGPT for automated grading of short-answer questions in mechanical ventilation examinations.* [Published study](https://doi.org/10.11157/fohpe-vol27iss1id958); [2025 primary preprint](https://arxiv.org/abs/2505.04645).
38. Convai Innovations. *Laya model card.* [Official checkpoint documentation and benchmarks](https://huggingface.co/convaiinnovations/laya). Developer-reported technical evidence; accessed 5 October 2026.
39. Convai Innovations / NandhaKishorM. *Laya runtime repository.* [Official implementation and linked deployment projects](https://github.com/NandhaKishorM/laya). Technical evidence; accessed 5 October 2026.
40. Convai Innovations. *Laya typed-decisions model card.* [Training, evaluation and calibration limits](https://huggingface.co/convaiinnovations/laya-typed-decisions). Synthetic-workflow evidence; accessed 5 October 2026.
