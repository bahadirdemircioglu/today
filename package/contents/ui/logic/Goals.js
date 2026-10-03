.pragma library

// Daily goal progress from Todoist's productivity stats (GET /tasks/completed/stats).
// The response shape is parsed defensively: anything unexpected yields null and the ring hides.
//   { days_items: [{ date: "YYYY-MM-DD", total_completed }], goals: { daily_goal, ... }, ... }

var REFRESH_MS = 15 * 60 * 1000;

// -> { completed, goal, date } | null
function parseStats(json, todayKey, fallbackGoal) {
    if (!json || typeof json !== "object") {
        return null;
    }
    var goal = json.goals && typeof json.goals.daily_goal === "number" ? json.goals.daily_goal
             : (typeof fallbackGoal === "number" ? fallbackGoal : null);
    if (goal === null || goal <= 0) {
        return null;
    }
    var completed = 0;
    var days = Array.isArray(json.days_items) ? json.days_items : [];
    for (var i = 0; i < days.length; i++) {
        if (days[i] && days[i].date === todayKey && typeof days[i].total_completed === "number") {
            completed = days[i].total_completed;
            break;
        }
    }
    return { completed: completed, goal: goal, date: todayKey };
}

// Progress to show: server count plus completions made here since the stats were fetched.
// -> { completed, goal, fraction, reached } | null
function progress(stats, todayKey, localSince) {
    if (!stats || stats.date !== todayKey) {
        return null;
    }
    var done = stats.completed + (localSince || 0);
    return {
        completed: done,
        goal: stats.goal,
        fraction: Math.min(1, done / stats.goal),
        reached: done >= stats.goal
    };
}

function needsRefresh(stats, fetchedAt, nowMs, todayKey) {
    return !stats || stats.date !== todayKey || nowMs - fetchedAt >= REFRESH_MS;
}
