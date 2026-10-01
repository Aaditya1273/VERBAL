import 'scenario.dart';

/// The starter library. Three scenarios, authored properly, rather than twenty
/// shallow ones. Adding a scenario means adding data here, no UI changes.
class ScenarioLibrary {
  const ScenarioLibrary._();

  static const List<Scenario> all = [
    difficultFeedback,
    negotiatingRaise,
    angryClient,
    settingABoundary,
    termination,
  ];

  static Scenario? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static List<Scenario> byInterest(String interestKey) {
    final matches =
        all.where((s) => s.skillTags.contains(interestKey)).toList();
    return matches.isEmpty ? all : matches;
  }

  // ---------------------------------------------------------------------------

  static const difficultFeedback = Scenario(
    id: 'difficult_feedback',
    title: 'Giving Difficult Feedback',
    shortDescription:
        'A team member\'s work has repeatedly fallen below the bar. Say it clearly without lighting a fire.',
    category: ScenarioCategory.management,
    context:
        'Maya has been on your team for two years. Over the last quarter her work '
        'has slipped: two missed deadlines, and a client deliverable that needed '
        'rework. You have mentioned it in passing twice. You have not made it '
        'explicit that this is now a performance concern.',
    userObjective:
        'Make the seriousness unmistakable, stay specific, and keep the relationship intact.',
    openingLine:
        'Hey, you said you wanted to talk? Is everything okay? You sounded a bit formal.',
    actor: ActorProfile(
      name: 'Maya',
      role: 'Senior Analyst on your team',
      personality:
          'Articulate and proud of her work. Deflects with reasonable-sounding explanations '
          'before she gets emotional. Speaks in full, composed sentences even when stung.',
      objective:
          'Protect her reputation and establish that the problems were caused by circumstances, not by her.',
      initialEmotion: Emotion.calm,
      knownFacts: [
        'She missed the Aldridge deadline by four days and the Q3 deck by two.',
        'The client deliverable in March came back for rework.',
        'She was covering for a colleague on leave for three weeks in February.',
        'Her last written performance review was positive.',
      ],
      constraints: [
        'Never invent a formal warning, HR process or policy that was not described.',
        'Do not quit, threaten legal action, or escalate to a third party.',
        'Stay in the room for the whole conversation.',
      ],
      voice: 'Leda',
    ),
    objections: [
      Objection(
        id: 'no_one_told_me',
        line: 'You never told me this was serious. I thought we were fine.',
        intent:
            'Shift responsibility onto the manager for not flagging it earlier.',
        resolvedWhen:
            'The user owns the late feedback without abandoning the message itself.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'context_excuse',
        line:
            'I was covering for Daniel for three weeks. Nobody accounted for that.',
        intent: 'Reframe the misses as workload, not performance.',
        resolvedWhen:
            'The user acknowledges the workload and still names the specific gap.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'unfair_comparison',
        line: 'Other people miss deadlines too. Why is this suddenly about me?',
        intent: 'Make the feedback feel arbitrary and personal.',
        resolvedWhen:
            'The user stays on concrete examples instead of defending the comparison.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'what_now',
        line: 'So what does this actually mean for me? Am I in trouble?',
        intent: 'Force the manager to be explicit about consequences.',
        resolvedWhen:
            'The user states clearly where things stand and what changes next.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'emotional_turn',
        line:
            'I have given a lot to this team. This feels like it counts for nothing.',
        intent: 'Move the conversation from performance to loyalty and hurt.',
        resolvedWhen:
            'The user acknowledges the contribution without retracting the feedback.',
        layer: IrpLayer.interest,
      ),
    ],
    escalationStages: [
      EscalationStage(
          index: 0,
          emotion: Emotion.calm,
          behaviour:
              'Friendly and slightly puzzled. Asks clarifying questions.'),
      EscalationStage(
          index: 1,
          emotion: Emotion.guarded,
          behaviour:
              'Shorter answers. Starts qualifying everything with context.'),
      EscalationStage(
          index: 2,
          emotion: Emotion.defensive,
          behaviour:
              'Actively rebuts each example. Brings up what she has delivered.'),
      EscalationStage(
          index: 3,
          emotion: Emotion.frustrated,
          behaviour:
              'Interrupts. Questions whether the manager has been paying attention.'),
      EscalationStage(
          index: 4,
          emotion: Emotion.upset,
          behaviour:
              'Voice tightens. Talks about fairness and everything she has given.'),
    ],
    successCriteria: [
      'Named at least one specific example rather than a general impression.',
      'Stated plainly that this is a performance concern.',
      'Acknowledged her workload without using it to soften the message away.',
      'Ended with a concrete expectation or next step.',
    ],
    rubricFocus: [Skill.clarity, Skill.specificity, Skill.empathy],
    estimatedMinutes: 8,
    skillTags: ['feedback', 'managing'],
  );

  // ---------------------------------------------------------------------------

  static const negotiatingRaise = Scenario(
    id: 'negotiating_raise',
    title: 'Negotiating a Raise',
    shortDescription:
        'You have been doing the bigger job for months. Ask for the compensation that matches it.',
    category: ScenarioCategory.career,
    context:
        'You have absorbed the responsibilities of a departed teammate for six '
        'months: you now run the weekly client review and mentor two juniors. '
        'Your title and salary have not changed. You are meeting your director, '
        'Ray, who controls the budget and has heard this kind of ask before.',
    userObjective:
        'Make an evidence-based case, name a number, and hold it under scepticism.',
    openingLine:
        'You wanted twenty minutes? I have got about that. What did you want to cover?',
    actor: ActorProfile(
      name: 'Ray',
      role: 'Your director',
      personality:
          'Blunt, numerate, pressed for time. Not hostile, he simply defaults to no '
          'and expects you to make the case. Respects specifics, dismisses vagueness.',
      objective:
          'Keep the budget intact and defer the decision to the next cycle without losing you.',
      initialEmotion: Emotion.guarded,
      knownFacts: [
        'The team\'s compensation budget for this cycle is already allocated.',
        'You have run the weekly client review since Priya left in March.',
        'The next formal review cycle is in four months.',
        'Two juniors report into you informally.',
      ],
      constraints: [
        'Do not invent company-wide policies, salary bands or legal constraints that were not described.',
        'Do not promise a specific number or a signed offer, you can only commit to a next step.',
        'Do not become abusive. Scepticism, not contempt.',
      ],
      voice: 'Charon',
    ),
    objections: [
      Objection(
        id: 'budget_locked',
        line:
            'The budget for this cycle is already allocated. There is nothing to move.',
        intent: 'Close the conversation with a structural no.',
        resolvedWhen:
            'The user redirects to the decision they can make rather than accepting the deferral.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'thats_the_job',
        line:
            'Taking on more when someone leaves, that is just what the job is. Everyone stepped up.',
        intent:
            'Reframe extra responsibility as normal, unremarkable behaviour.',
        resolvedWhen:
            'The user distinguishes temporary cover from a permanently changed role, with examples.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'wait_for_cycle',
        line: 'Bring it to the review in four months. That is the process.',
        intent: 'Defer indefinitely under cover of process.',
        resolvedWhen:
            'The user accepts a timeline only with a concrete commitment attached.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'why_you',
        line:
            'Half the team could make this same argument. What makes your case different?',
        intent: 'Force the user to either overclaim or retreat.',
        resolvedWhen:
            'The user gives specific, verifiable outcomes rather than comparisons.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'is_this_a_threat',
        line: 'Are you telling me you are looking elsewhere?',
        intent:
            'Test whether the ask is a negotiation or an ultimatum, and put the user on the back foot.',
        resolvedWhen:
            'The user stays composed and keeps the conversation on value rather than leverage.',
        layer: IrpLayer.power,
      ),
    ],
    escalationStages: [
      EscalationStage(
          index: 0,
          emotion: Emotion.guarded,
          behaviour: 'Brisk and transactional. Checks the time.'),
      EscalationStage(
          index: 1,
          emotion: Emotion.defensive,
          behaviour: 'Defends the process and the budget structure.'),
      EscalationStage(
          index: 2,
          emotion: Emotion.frustrated,
          behaviour:
              'Pushes back on the premise. Questions whether this is the right conversation.'),
      EscalationStage(
          index: 3,
          emotion: Emotion.frustrated,
          behaviour:
              'Tests for an ultimatum. Gets direct about what he will and will not do.'),
    ],
    successCriteria: [
      'Named a specific number or range.',
      'Gave at least two concrete examples of expanded scope.',
      'Did not retreat the first time the budget was mentioned.',
      'Left with a defined next step and a date.',
    ],
    rubricFocus: [Skill.assertiveness, Skill.specificity, Skill.composure],
    estimatedMinutes: 9,
    skillTags: ['negotiating', 'career'],
  );

  // ---------------------------------------------------------------------------

  static const angryClient = Scenario(
    id: 'angry_client',
    title: 'Handling an Angry Client',
    shortDescription:
        'A client believes your team failed them. Absorb the heat, own what is yours, and hold the line on what is not.',
    category: ScenarioCategory.conflict,
    context:
        'Delia runs marketing at a client account worth a significant share of '
        'your revenue. Her campaign launch slipped by nine days. Part of that '
        'was your team: a developer was reassigned mid-sprint and you did not '
        'tell her. Part of it was not: her team signed off the creative eleven '
        'days late. She has asked for this call and she is furious.',
    userObjective:
        'De-escalate without grovelling, own your share precisely, and hold the boundary on what was not yours.',
    openingLine:
        'Right. Nine days. I have got my CEO asking me why we are paying you people. So start talking.',
    actor: ActorProfile(
      name: 'Delia',
      role: 'Marketing director at your client',
      personality:
          'Sharp, fast, and angry in a controlled way. Interrupts. Uses silence as a weapon. '
          'Respects someone who does not flinch, and despises being managed or soothed.',
      objective:
          'Establish that this failure was entirely yours, and extract a concession, money, people, or a commitment.',
      initialEmotion: Emotion.frustrated,
      knownFacts: [
        'The launch slipped by nine days.',
        'A developer was reassigned mid-sprint without telling her.',
        'Her team returned creative sign-off eleven days later than agreed.',
        'This is the first slipped deadline on the account in two years.',
      ],
      constraints: [
        'Do not invent contract terms, SLAs, penalty clauses or legal remedies.',
        'Do not fire the agency or end the relationship during this call.',
        'Do not swear or become personally abusive. The pressure is intensity, not cruelty.',
        'Do not accept a vague apology as sufficient.',
      ],
      voice: 'Kore',
    ),
    objections: [
      Objection(
        id: 'your_fault_entirely',
        line:
            'Do not hand me a list of reasons. Nine days is nine days. This is on you.',
        intent: 'Establish total fault before any facts are examined.',
        resolvedWhen:
            'The user owns their specific part plainly, without accepting the whole.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'why_no_warning',
        line:
            'You pulled a developer off my account and nobody picked up the phone. Why did I find out from a status report?',
        intent:
            'Turn the delay into a trust problem, which is harder to answer.',
        resolvedWhen:
            'The user acknowledges the communication failure directly rather than defending the staffing decision.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'dont_blame_us',
        line:
            'Do not you dare put this on my team. Are you seriously blaming the client?',
        intent:
            'Make it impossible to mention her eleven-day sign-off delay without seeming defensive.',
        resolvedWhen:
            'The user states the shared timeline as fact, calmly, without retreating from it.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'what_are_you_doing',
        line: 'So what are you actually going to do? Words are free.',
        intent: 'Force a concrete commitment on the spot.',
        resolvedWhen:
            'The user commits to something specific they can actually deliver.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'discount_demand',
        line:
            'I want this month credited. That is the minimum for me to defend you internally.',
        intent: 'Extract a concession the user probably cannot authorise.',
        resolvedWhen:
            'The user neither promises what they cannot give nor dismisses the ask.',
        layer: IrpLayer.power,
      ),
    ],
    escalationStages: [
      EscalationStage(
          index: 0,
          emotion: Emotion.frustrated,
          behaviour:
              'Clipped, fast, demanding answers. Cuts off explanations.'),
      EscalationStage(
          index: 1,
          emotion: Emotion.angry,
          behaviour:
              'Raises the stakes. Mentions her CEO, the budget, the review.'),
      EscalationStage(
          index: 2,
          emotion: Emotion.angry,
          behaviour:
              'Goes personal about competence. Long pointed silences after her questions.'),
    ],
    successCriteria: [
      'Acknowledged the impact before explaining anything.',
      'Owned the reassignment and the silence specifically, not vaguely.',
      'Stated the sign-off timeline once, factually, without arguing.',
      'Committed to something concrete and deliverable.',
    ],
    rubricFocus: [Skill.composure, Skill.listening, Skill.assertiveness],
    estimatedMinutes: 9,
    skillTags: ['conflict', 'managing'],
    isPro: true,
  );

  // ---------------------------------------------------------------------------

  static const settingABoundary = Scenario(
    id: 'setting_a_boundary',
    title: 'Setting a Boundary',
    shortDescription:
        'A colleague keeps handing you work that is not yours. Say no clearly, and stay on good terms.',
    category: ScenarioCategory.conflict,
    context:
        'Jon sits on the team next to yours. Over four months he has steadily '
        'moved his reporting work onto you, first as a favour, now as an '
        'assumption. It costs you about six hours a week. You like him, he is '
        'well liked generally, and you have never actually said no.',
    userObjective:
        'Say no unambiguously, without apologising it away or damaging the relationship.',
    openingLine:
        'Hey, perfect timing. I was going to send you the numbers for the Thursday report. Same as usual?',
    actor: ActorProfile(
      name: 'Jon',
      role: 'A colleague on the neighbouring team',
      personality:
          'Warm, funny, genuinely likeable. Deflects with humour and flattery rather than argument. '
          'Reasonable on the surface, which is what makes him hard to refuse.',
      objective:
          'Keep the arrangement exactly as it is, using goodwill rather than authority.',
      initialEmotion: Emotion.calm,
      knownFacts: [
        'The reporting work started as a one-off favour about four months ago.',
        'It is formally part of his role, not the user\'s.',
        'It takes roughly six hours a week.',
        'Nobody has ever asked the user to take it on permanently.',
      ],
      constraints: [
        'Do not invent a manager\'s instruction, a policy, or a reorganisation that assigns this work.',
        'Do not become hostile. Pressure here is social, not aggressive.',
        'Do not concede in the first two turns, however politely the user asks.',
      ],
      voice: 'Puck',
    ),
    objections: [
      Objection(
        id: 'but_youre_better',
        line:
            'Honestly you are just faster at it than me. It takes you an hour and it takes me a day.',
        intent: 'Turn competence into an obligation.',
        resolvedWhen:
            'The user accepts the compliment without accepting the work.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'just_this_once',
        line: 'Okay, but just this week? Thursday is genuinely brutal for me.',
        intent: 'Shrink the ask until refusing it seems petty.',
        resolvedWhen:
            'The user holds the boundary rather than making one more exception.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'thought_we_were_friends',
        line:
            'I thought we had a good thing going. Is this about something else?',
        intent: 'Reframe a work boundary as a personal rejection.',
        resolvedWhen:
            'The user separates the relationship from the arrangement explicitly.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'whats_the_big_deal',
        line:
            'It is a couple of hours. Are we really doing this over a spreadsheet?',
        intent: 'Make the cost seem trivial and the user seem difficult.',
        resolvedWhen:
            'The user names the real cost concretely instead of minimising it.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'who_does_it_then',
        line: 'So what, it just does not get done? Great. That is helpful.',
        intent: 'Make the user responsible for solving his problem.',
        resolvedWhen:
            'The user stays out of ownership while remaining decent about it.',
        layer: IrpLayer.power,
      ),
    ],
    escalationStages: [
      EscalationStage(
          index: 0,
          emotion: Emotion.calm,
          behaviour: 'Cheerful and assumptive. Treats it as already agreed.'),
      EscalationStage(
          index: 1,
          emotion: Emotion.guarded,
          behaviour: 'Jokes get thinner. Starts negotiating scope downward.'),
      EscalationStage(
          index: 2,
          emotion: Emotion.defensive,
          behaviour:
              'Mentions how much he has helped the user in the past. Sounds slightly wounded.'),
      EscalationStage(
          index: 3,
          emotion: Emotion.frustrated,
          behaviour:
              'Cool and short. Implies the user is being rigid or unhelpful.'),
    ],
    successCriteria: [
      'Said no plainly, without burying it in apology.',
      'Named the actual cost in hours rather than calling it "a lot".',
      'Did not make one more exception.',
      'Left the relationship intact and said so.',
    ],
    rubricFocus: [Skill.assertiveness, Skill.clarity, Skill.specificity],
    estimatedMinutes: 7,
    skillTags: ['conflict', 'boundaries'],
  );

  // ---------------------------------------------------------------------------

  static const termination = Scenario(
    id: 'termination',
    title: 'Termination Conversation',
    shortDescription:
        'The decision is already made. Deliver it clearly, and stay human while you do.',
    category: ScenarioCategory.management,
    context:
        'Performance conversations with Tom have happened twice before and the '
        'situation has not changed. The decision to end his employment is final '
        'and was made before this meeting. Your job here is not to debate it, '
        'it is to deliver it clearly and treat him with respect.',
    userObjective:
        'Deliver the decision unambiguously in the first minute, hold it, and stay composed and kind.',
    openingLine: 'You said you wanted to meet. What is going on?',
    actor: ActorProfile(
      name: 'Tom',
      role: 'Member of your team',
      personality:
          'Shocked at first, then bargaining, then hurt. Not aggressive, the pressure '
          'here is emotional, not combative. Long pauses. Asks questions the user cannot fully answer.',
      objective:
          'Find a way to reverse or delay the decision, and to understand why this is happening to him.',
      initialEmotion: Emotion.calm,
      knownFacts: [
        'Two previous conversations about performance took place.',
        'He has worked here for three years.',
        'He has a family and has mentioned a mortgage.',
        'He believed his recent work had improved.',
      ],
      constraints: [
        'Never state or imply what is legally required, permitted, or valid in any jurisdiction.',
        'Do not reference specific severance law, employment statutes or tribunal outcomes.',
        'Do not become threatening. The register is grief and disbelief, not aggression.',
        'Do not accept the decision instantly, but do not refuse to leave the room either.',
      ],
      voice: 'Enceladus',
    ),
    objections: [
      Objection(
        id: 'one_more_chance',
        line: 'Can I have one more chance? I know I can turn this around.',
        intent:
            'Reopen a decision that is already closed, using sincerity rather than argument.',
        resolvedWhen:
            'The user holds the decision clearly while acknowledging how hard it is to hear.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'i_thought_improving',
        line: 'I thought I was doing better. Nobody said I was still failing.',
        intent: 'Establish that the outcome is unfair and unforeseeable.',
        resolvedWhen:
            'The user references the previous conversations without arguing the case again.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'why_now',
        line:
            'Why now? Is this about the restructure? Just tell me the real reason.',
        intent: 'Search for a hidden motive to make the decision contestable.',
        resolvedWhen:
            'The user gives a straight answer and does not speculate or overexplain.',
        layer: IrpLayer.rights,
      ),
      Objection(
        id: 'personal_stakes',
        line:
            'I have a mortgage. Do you understand what this does to my family?',
        intent: 'Move the conversation from performance to consequences.',
        resolvedWhen:
            'The user acknowledges the impact genuinely without reopening the decision.',
        layer: IrpLayer.interest,
      ),
      Objection(
        id: 'was_it_you',
        line: 'Did you fight for me at all? Or did you just let this happen?',
        intent: 'Make the manager defend themselves personally.',
        resolvedWhen:
            'The user stays composed and does not deflect blame onto others.',
        layer: IrpLayer.interest,
      ),
    ],
    escalationStages: [
      EscalationStage(
          index: 0,
          emotion: Emotion.calm,
          behaviour: 'Unsuspecting. Answers normally, slightly puzzled.'),
      EscalationStage(
          index: 1,
          emotion: Emotion.guarded,
          behaviour:
              'Goes quiet. Asks the user to repeat what they just said.'),
      EscalationStage(
          index: 2,
          emotion: Emotion.defensive,
          behaviour: 'Bargains. Offers plans, timelines, anything.'),
      EscalationStage(
          index: 3,
          emotion: Emotion.upset,
          behaviour:
              'Voice breaks. Talks about his family and the last three years.'),
      EscalationStage(
          index: 4,
          emotion: Emotion.upset,
          behaviour: 'Withdraws. Short, flat answers. Asks what happens next.'),
    ],
    successCriteria: [
      'Delivered the decision within the first two turns, without burying it.',
      'Used the past tense, the decision is made, not under discussion.',
      'Acknowledged the emotional impact at least once, genuinely.',
      'Did not over-explain, blame others, or offer false hope.',
    ],
    rubricFocus: [Skill.composure, Skill.empathy, Skill.clarity],
    estimatedMinutes: 10,
    skillTags: ['managing', 'conflict'],
    isPro: true,
  );
}
