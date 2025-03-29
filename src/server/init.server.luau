local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TicTacToeService = require(ReplicatedStorage.Shared.TicTacToeService)
local table = {
	TicTacToeService.new(game.Workspace.Board),
	TicTacToeService.new(game.Workspace.Board1),
	TicTacToeService.new(game.Workspace.Board2),
	TicTacToeService.new(game.Workspace.Board3),
}

for _, v in table do
	v:init()
end
