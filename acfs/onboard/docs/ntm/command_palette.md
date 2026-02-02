# NTM Command Palette (`command_palette.md`)
#
# This file defines the prompts shown in `ntm palette`.
#
# Usage:
#   - `ntm palette [session]` (or press the tmux popup key after `ntm bind`, default: F6)
#   - In the palette: type to filter, `1-9` quick-select, `Enter` select, `?` for help
#   - Target selection: press `1-4` to choose recipients (All / Claude / Codex / Gemini)
#
# Preview pane:
#   - Shows targets + prompt metadata (lines/chars) and lightweight warning badges.
#
# Format:
#   ## Category Name
#   ### command_key | Display Label
#   The prompt text (can be multiple lines)
#
# Prompt design tips:
#   - Prefer short, explicit, reversible steps; avoid “do everything”.
#   - If something is destructive (rm/git reset), make it opt-in and ask for confirmation.
#   - Include one concrete “next command” when possible.
#
# NOTE: Recents/favorites/pinning are planned but may not be available in all builds yet.

## Analysis & Review

### fresh_review | Fresh Review
Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover. 

### check_other_agents_work | Check Other Agents Work
Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep! Use ultrathink. 

### randomly_inspect_code | Randomly Inspect Code
I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file. 

### analyze_beads_and_allocate | Analyze Beads and Allocate
Re-read AGENTS.md first. Then, can you try using bv to get some insights on what each agent should most usefully work on? Then share those insights with the other agents via agent mail and strongly suggest in your messages the optimal work for each one and explain how/why you came up with that using bv. Use ultrathink. 

### check_orm_and_schemas | Check ORM and Schemas
Now reread AGENTS.md, read your README.md, and then I want you to use ultrathink to super carefully and critically read the entire data ORM schema/models and look for any issues or problems, conceptual mistakes, logical errors, or anything that doesn't fit your understanding of the business strategy and accepted best practices for the design and architecture of databases for these sorts of ecommerce/saas projects/companies. 

### scrutinize_and_improve_workflow_and_ui | Scrutinize and Improve Workflow and UI
Great, now I want you to super carefully scrutinize every aspect of the application workflow and implementation and look for things that just seem sub-optimal or even wrong/mistaken to you, things that could very obviously be improved from a user-friendliness and intuitiveness standpoint, places where our UI/UX could be improved and polished to be slicker, more visually appealing, and more premium feeling and just ultra high quality, like Stripe-level apps. 

### apply_ubs | Apply UBS
Read about the ubs tool in AGENTS.md. Now run UBS and investigate and fix literally every single UBS issue once you determine (after reasoned consideration and close inspection) that it's legit. 

## Coding & Development

### fix_bug | Fix Bug
I want you to very carefully diagnose and then fix the root underlying cause of the bugs/errors shown here, but fix them FOR REAL, not a superficial "bandaid" fix! Here are the details: 

### create_tests | Create Tests
Do we have full unit test coverage without using mocks/fake stuff? What about complete e2e integration test scripts with great, detailed logging? If not, then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid with detailed comments. 

### leverage_tanstack_libraries | Leverage TanStack Libraries
Ok I want you to look through the ENTIRE project and look for areas where, if we leveraged one of the many TanStack libraries (e.g., query, table, forms, etc), we could make part of the code much better, simpler, more performant, more maintainable, elegant, shorter, more reliable, etc. 

### build_ui_ux | Build UI/UX
I also want you to do a spectacular job building absolutely world-class UI/UX components, with an intense focus on making the most visually appealing, user-friendly, intuitive, slick, polished, "Stripe level" of quality UI/UX possible for this that leverages the good libraries that are already part of the project. 

## Documentation

### complete_docusaurus_site | Complete Docusaurus Site
Now I need you to look through the existing documentation in our docusaurus site here and look for the (many, many) instances of functionality in our project that are not described or explained at all yet (or explained inadequately) in the docusaurus site, and then create and expand the documentation in the site to cover these in an exhaustive, intuitive, helpful, useful, pragmatic way. Don't just make a dump of methods, parameters, etc. Add actually well-written narrative explaining what the stuff does, how it is organized, etc. to help another developer understand how it all works so that they can usefully contribute to the system. 

### improve_readme | Improve README
Be sure to check your agent mail and to promptly respond if needed to any messages, and also acknowledge any contact requests; make sure you know the names of all active agents using the MCP Agent Mail system. 

### revise_readme | Revise README
We need to revise the README too for these changes (don't write about these as "changes" however, make it read like it was always like that, we don't have any users yet!) 

### add_missing_features_to_readme | Add Missing Features to README
What else can we put in there to make the README longer and more detailed about what we built, why it's useful, how it works, the algorithms/design principles used, etc. This is incremental NEW content, not replacement for what is there already. 

## Planning & Workflow

### combine_plans_into_hybrid | Combine Plans Into Hybrid
I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan (you should simply update your existing document for your original plan with the revisions) that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan that best achieves our stated goals and will work the best in real-world practice to solve the problems we are facing and our overarching goals while ensuring the extreme success of the enterprise as best as possible; you should provide me with a complete series of git-diff style changes to your original plan to turn it into the new, enhanced, much longer and detailed plan that integrates the best of all the plans with every good idea included (you don't need to mention which ideas came from which models in the final revised enhanced plan): 

### improve_beads | Improve Beads
Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! 

### turn_plan_into_beads | Turn Plan Into Beads
OK so please take ALL of that and elaborate on it more and then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.) 

### use_bv | Use BV
Use bv with the robot flags (see AGENTS.md for info on this) to find the most impactful bead(s) to work on next and then start on it. Remember to mark the beads appropriately and communicate with your fellow agents. 

### next_bead | Next Bead
Pick the next bead you can actually do usefully now and start coding on it immediately; communicate what you're working on to your fellow agents and mark beads appropriately as you work. And respond to any agent mail messages you've received. 

### work_on_your_beads | Work on Your Beads
OK, so start systematically and methodically and meticulously and diligently executing those remaining beads tasks that you created in the optimal logical order! Don't forget to mark beads as you work on them. 

### do_all_of_it | Do All Of It
OK, please do ALL of that now. Track work via br beads (no markdown TODO lists): create/claim/update/close beads as you go so nothing gets lost, and keep communicating via Agent Mail when you start/finish work. 

## Git & Operations

### git_commit | Git Commit
Now, based on your knowledge of the project, commit all changed files now in a series of logically connected groupings with super detailed commit messages for each and then push. Take your time to do it right. Don't edit the code at all. Don't commit obviously ephemeral files. Use ultrathink. 

### do_gh_flow | Do GH Flow
Do all the GitHub stuff: commit, deploy, create tag, bump version, release, monitor gh actions, compute checksums, etc. 

## Agent Coordination

### default_new_agent | Default New Agent
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents. Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages. Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately. When you're not sure what to do next, use the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. 

### check_and_respond_to_mail | Check and Respond to Mail
Be sure to check your agent mail and to promptly respond if needed to any messages, and also acknowledge any contact requests; make sure you know the names of all active agents using the MCP Agent Mail system. 

### introduce_to_fellow_agents | Introduce to Fellow Agents
Before doing anything else, read ALL of AGENTS.md, then register with MCP Agent Mail and introduce yourself to the other agents.

### check_project_inbox | Check Project Inbox
Check the project inbox for any new messages from other agents or the human overseer.
Run 'ntm mail inbox' to see the full list of messages.

### start_out_with_agent_mail | Start Out With Agent Mail
Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages. Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately. When you're really not sure what to do, pick the next bead that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. Use ultrathink.
## Investigation

### read_agents_and_investigate | Read Agents and Investigate
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. 

### reread_agents_md | Reread AGENTS.md
Reread AGENTS.md so it's still fresh in your mind. 

## Quick Commands

### ultrathink | Ultrathink
Use ultrathink. 
