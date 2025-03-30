local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TicTacToeService = require(ReplicatedStorage.Shared.TicTacToeService)
local table = CollectionService:GetTagged("Board")

for _, board in table do
	local tictactoe = TicTacToeService.new(board)
	tictactoe:init()
	tictactoe.onGameEnd.Event:Connect(function(winner)
		local winnerName = typeof(winner) == "Instance" and winner.Name or winner
		print("The winner is "
			.. winnerName
		)
		task.wait(3)
		tictactoe:init()
	end)
end