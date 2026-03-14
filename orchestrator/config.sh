PLANNER_TIMEOUT=45        # minutes (includes project review + web research)
ACTOR_TIMEOUT=60          # minutes per actor (up to MAX_ACTORS per session)
VERIFY_TIMEOUT=15         # minutes (tests, build, git/doc checks)
MAX_ACTORS=4              # number of bets to execute sequentially
CRITIC_TIMEOUT=30         # minutes (structural analysis, no code changes)
CRITIC_INTERVAL=5         # run every N successful sessions
