--!strict
-- Per-player token bucket. `limiter:take(player)` returns false when the player is
-- sending a remote faster than allowed.

local Players = game:GetService("Players")

export type RateLimiter = {
	take: (self: RateLimiter, player: Player) -> boolean,
}

local RateLimiter = {}

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	local buckets: { [Player]: { tokens: number, at: number } } = {}

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	local self = {}
	function self.take(_: RateLimiter, player: Player): boolean
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = { tokens = capacity, at = now }
			buckets[player] = b
		end
		b.tokens = math.min(capacity, b.tokens + (now - b.at) * refillPerSecond)
		b.at = now
		if b.tokens < 1 then
			return false
		end
		b.tokens -= 1
		return true
	end
	return (self :: any) :: RateLimiter
end

return RateLimiter
