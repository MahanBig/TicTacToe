--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Define the type for the game instance object
export type TicTacToeGame = {
	board: Model?, -- Can be nil after destroy
	gameOver: boolean,
	movesMade: number,
	playerX: Player?, -- Can be nil before game starts or after destroy
	connections: { RBXScriptConnection }, -- A table holding event connections
	xModelReference: Model?, -- Can be nil after destroy
	oModelReference: Model?, -- Can be nil after destroy
	onButtonChanged: BindableEvent,
	onGameEnd: BindableEvent,

	-- Methods associated with this type (implemented below on the Shared table)
	init: (self: TicTacToeGame) -> (),
	destroy: (self: TicTacToeGame) -> (),
}

local Shared = {}
Shared.__index = Shared -- Instances created will use Shared for methods

local Private = {}

-- Constants for AI and players
local AI_PLAYER = "O"
local HUMAN_PLAYER = "X"
local EMPTY_SLOT = ""

-- Constants for Minimax scores
local SCORE_AI_WIN = 10
local SCORE_HUMAN_WIN = -10
local SCORE_DRAW = 0

-- Name to identify placed visual models for easy cleanup
local PLACED_MODEL_NAME = "TicTacToeVisual"

-- ==================================
--      HELPER FUNCTIONS START
-- ==================================

-- --- Visual Model Placement ---
-- (No changes needed in these helpers)

function Private.placeVisualModel(button: BasePart, modelToClone: Model?)
	if not modelToClone then
		warn("Attempted to place visual model, but model reference was nil.")
		return
	end
	local visualModel = modelToClone:Clone() :: Model
	visualModel.Name = PLACED_MODEL_NAME
	if not visualModel.PrimaryPart then
		warn("Visual model", modelToClone.Name, "is missing a PrimaryPart. Cannot accurately position.")
		visualModel.Parent = button
		return
	end
	local buttonSize = button.Size
	local modelPrimaryPart = visualModel.PrimaryPart :: BasePart
	local modelOffsetY = modelPrimaryPart.Size.Y / 2
	local targetCFrame = button.CFrame * CFrame.new(0, (buttonSize.Y / 2) + modelOffsetY + 0.1, 0)
	visualModel:PivotTo(targetCFrame)
	visualModel.Parent = button
end

function Private.removeVisualModel(button: BasePart)
	local existingVisual = button:FindFirstChild(PLACED_MODEL_NAME)
	if existingVisual and existingVisual:IsA("Model") then
		existingVisual:Destroy()
	end
end

-- --- Board Interaction ---
-- (No changes needed in these helpers)

function Private.getButton(board: Model, row: number, col: number): BasePart?
	for _, button in ipairs(board:GetChildren()) do
		if button:IsA("BasePart") and button:GetAttribute("Row") == row and button:GetAttribute("Column") == col then
			return button
		end
	end
	warn("getButton failed to find button at Row:", row, "Col:", col, "in Board:", board:GetFullName())
	return nil
end

function Private.checkWin(board: Model, player: string): boolean
	local winPatterns = {
		{ { 1, 1 }, { 1, 2 }, { 1, 3 } },
		{ { 2, 1 }, { 2, 2 }, { 2, 3 } },
		{ { 3, 1 }, { 3, 2 }, { 3, 3 } },
		{ { 1, 1 }, { 2, 1 }, { 3, 1 } },
		{ { 1, 2 }, { 2, 2 }, { 3, 2 } },
		{ { 1, 3 }, { 2, 3 }, { 3, 3 } },
		{ { 1, 1 }, { 2, 2 }, { 3, 3 } },
		{ { 1, 3 }, { 2, 2 }, { 3, 1 } },
	}
	for _, pattern in ipairs(winPatterns) do
		local win = true
		for _, pos in ipairs(pattern) do
			local button = Private.getButton(board, pos[1], pos[2])
			local stateValue = button and button:FindFirstChild("State") :: StringValue?
			if not stateValue or stateValue.Value ~= player then
				win = false
				break
			end
		end
		if win then
			return true
		end
	end
	return false
end

-- --- Board State Conversion for AI ---
-- (No changes needed in these helpers)

function Private.getCurrentBoardState(boardModel: Model): { { string } }
	local boardTable = { { "", "", "" }, { "", "", "" }, { "", "", "" } }
	for row = 1, 3 do
		for col = 1, 3 do
			local button = Private.getButton(boardModel, row, col)
			if button then
				local stateValue = button:FindFirstChild("State") :: StringValue?
				if stateValue and stateValue.Value ~= EMPTY_SLOT then
					boardTable[row][col] = stateValue.Value
				end
			else
				warn(
					"getCurrentBoardState: Could not find button part at Row:",
					row,
					"Col:",
					col,
					"in Board:",
					boardModel:GetFullName()
				)
			end
		end
	end
	return boardTable
end

-- ==================================
--      MINIMAX AI LOGIC START
-- (No changes needed in these helpers)
-- ==================================

function Private.checkTableWin(boardTable: { { string } }, player: string): boolean
	for i = 1, 3 do
		if boardTable[i][1] == player and boardTable[i][2] == player and boardTable[i][3] == player then
			return true
		end
		if boardTable[1][i] == player and boardTable[2][i] == player and boardTable[3][i] == player then
			return true
		end
	end
	if boardTable[1][1] == player and boardTable[2][2] == player and boardTable[3][3] == player then
		return true
	end
	if boardTable[1][3] == player and boardTable[2][2] == player and boardTable[3][1] == player then
		return true
	end
	return false
end

function Private.isTableDraw(boardTable: { { string } }): boolean
	for r = 1, 3 do
		for c = 1, 3 do
			if boardTable[r][c] == EMPTY_SLOT then
				return false
			end
		end
	end
	return not Private.checkTableWin(boardTable, AI_PLAYER) and not Private.checkTableWin(boardTable, HUMAN_PLAYER)
end

function Private.evaluateBoard(boardTable: { { string } }): number?
	if Private.checkTableWin(boardTable, AI_PLAYER) then
		return SCORE_AI_WIN
	elseif Private.checkTableWin(boardTable, HUMAN_PLAYER) then
		return SCORE_HUMAN_WIN
	elseif Private.isTableDraw(boardTable) then
		return SCORE_DRAW
	else
		return nil
	end
end

function Private.getAvailableMoves(boardTable: { { string } }): { { row: number, col: number } }
	local moves = {}
	for r = 1, 3 do
		for c = 1, 3 do
			if boardTable[r][c] == EMPTY_SLOT then
				table.insert(moves, { row = r, col = c })
			end
		end
	end
	return moves
end

function Private.minimax(boardTable: { { string } }, depth: number, isMaximizing: boolean): number
	local score = Private.evaluateBoard(boardTable)
	if score ~= nil then
		return score
	end
	local availableMoves = Private.getAvailableMoves(boardTable)
	local bestScore = isMaximizing and -math.huge or math.huge
	for _, move in ipairs(availableMoves) do
		local player = isMaximizing and AI_PLAYER or HUMAN_PLAYER
		boardTable[move.row][move.col] = player
		local currentScore = Private.minimax(boardTable, depth + 1, not isMaximizing)
		boardTable[move.row][move.col] = EMPTY_SLOT
		if isMaximizing then
			bestScore = math.max(bestScore, currentScore)
		else
			bestScore = math.min(bestScore, currentScore)
		end
	end
	return bestScore
end

function Private.findBestMove(boardModel: Model): { row: number, col: number }?
	local boardTable = Private.getCurrentBoardState(boardModel)
	local bestScore = -math.huge
	local bestMove = nil
	local availableMoves = Private.getAvailableMoves(boardTable)
	if #availableMoves == 0 then
		return nil
	end
	for _, move in ipairs(availableMoves) do
		boardTable[move.row][move.col] = AI_PLAYER
		local moveScore = Private.minimax(boardTable, 0, false)
		boardTable[move.row][move.col] = EMPTY_SLOT
		if moveScore > bestScore then
			bestScore = moveScore
			bestMove = move
		end
	end
	if not bestMove and #availableMoves > 0 then
		warn("Minimax couldn't determine best move, picking first available.")
		return availableMoves[1]
	end
	return bestMove
end

function Private.getAIMove(boardModel: Model): BasePart?
	print("AI is thinking for board:", boardModel:GetFullName())
	local bestMoveCoords = Private.findBestMove(boardModel)
	if bestMoveCoords then
		print("AI chose:", bestMoveCoords.row, bestMoveCoords.col, "for board:", boardModel:GetFullName())
		return Private.getButton(boardModel, bestMoveCoords.row, bestMoveCoords.col)
	else
		warn("AI could not find a valid move for board:", boardModel:GetFullName())
		return nil
	end
end

-- ==================================
--      GAME LOGIC START
-- ==================================

--[[* Handles clicks on the board buttons during the game *]]
-- Corrected type annotation for 'self'
function Private.onButtonClick(self: TicTacToeGame, button: BasePart, playerWhoClicked: Player)
	if self.gameOver then
		print("Game is over on board:", self.board and self.board:GetFullName() or "N/A")
		return
	end
	if self.playerX and playerWhoClicked ~= self.playerX then
		print(
			playerWhoClicked.Name
				.. " cannot play, it's "
				.. self.playerX.Name
				.. "'s turn/game on board "
				.. (self.board and self.board:GetFullName() or "N/A")
		)
		return
	end

	local stateValue = button:FindFirstChild("State") :: StringValue?
	if not stateValue or stateValue.Value ~= EMPTY_SLOT then
		print("Button already occupied or state missing on board:", self.board and self.board:GetFullName() or "N/A")
		return
	end

	if not self.playerX then
		self.playerX = playerWhoClicked
		print(
			self.playerX.Name .. " has started the game as X on board:",
			self.board and self.board:GetFullName() or "N/A"
		)
	end

	print(
		"Player",
		playerWhoClicked.Name,
		"clicked",
		button:GetAttribute("Row"),
		button:GetAttribute("Column"),
		"on board",
		self.board:GetFullName()
	)
	stateValue.Value = HUMAN_PLAYER
	Private.placeVisualModel(button, self.xModelReference)
	self.movesMade += 1
	self.onButtonChanged:Fire(button, HUMAN_PLAYER, playerWhoClicked)

	local boardToCheck = self.board :: Model
	if Private.checkWin(boardToCheck, HUMAN_PLAYER) then
		local winnerName = self.playerX and self.playerX.Name or "Player X"
		print(winnerName .. " wins on board:", boardToCheck:GetFullName())
		self.gameOver = true
		self.onGameEnd:Fire(self.playerX)
		return
	elseif self.movesMade >= 9 then
		print("Draw on board:", boardToCheck:GetFullName())
		self.gameOver = true
		self.onGameEnd:Fire("Draw")
		return
	end

	task.wait(0.1)
	if self.gameOver then
		return
	end

	local aiMoveButton = Private.getAIMove(boardToCheck)
	if aiMoveButton then
		local aiStateValue = aiMoveButton:FindFirstChild("State") :: StringValue?
		if aiStateValue and aiStateValue.Value == EMPTY_SLOT then
			aiStateValue.Value = AI_PLAYER
			Private.placeVisualModel(aiMoveButton, self.oModelReference)
			self.movesMade += 1
			self.onButtonChanged:Fire(aiMoveButton, AI_PLAYER, nil)

			if Private.checkWin(boardToCheck, AI_PLAYER) then
				print("AI wins on board:", boardToCheck:GetFullName())
				self.gameOver = true
				self.onGameEnd:Fire("AI")
				return
			elseif self.movesMade >= 9 then
				print("Draw on board:", boardToCheck:GetFullName())
				self.gameOver = true
				self.onGameEnd:Fire("Draw")
				return
			end
		elseif aiStateValue then
			warn(
				"AI chose an already occupied button:",
				aiMoveButton:GetFullName(),
				"State:",
				aiStateValue.Value,
				"Board:",
				boardToCheck:GetFullName()
			)
		else
			warn(
				"AI chose a button part without a 'State' StringValue:",
				aiMoveButton:GetFullName(),
				"Board:",
				boardToCheck:GetFullName()
			)
		end
	elseif not self.gameOver then
		local currentBoardState = Private.getCurrentBoardState(boardToCheck)
		if Private.isTableDraw(currentBoardState) then
			print("Draw confirmed (AI returned no move) on board:", boardToCheck:GetFullName())
			self.gameOver = true
			self.onGameEnd:Fire("Draw")
		else
			warn("AI returned no move, but game state is not a draw or win. Board:", boardToCheck:GetFullName())
		end
	end
end

--[[* Initializes or resets the board state and visuals *]]
-- Corrected type annotation for 'self'
function Private.InitializeBoard(self: TicTacToeGame)
	print("Initializing board:", self.board and self.board:GetFullName() or "N/A")
	self.gameOver = false
	self.movesMade = 0
	self.playerX = nil

	if self.connections then
		for _, conn in pairs(self.connections) do
			conn:Disconnect()
		end
		table.clear(self.connections)
	else
		self.connections = {}
	end

	if not self.board or not self.board:IsA("Model") then
		warn("InitializeBoard: self.board is nil or not a Model!")
		return
	end

	for _, button in ipairs(self.board:GetChildren()) do
		if button:IsA("BasePart") and button:GetAttribute("Column") and button:GetAttribute("Row") then
			Private.removeVisualModel(button)

			local stateValue = button:FindFirstChild("State") :: StringValue?
			if not stateValue then
				stateValue = Instance.new("StringValue")
				stateValue.Name = "State"
				stateValue.Parent = button
			end
			stateValue.Value = EMPTY_SLOT

			local clickDetector = button:FindFirstChildOfClass("ClickDetector")
			if not clickDetector then
				clickDetector = Instance.new("ClickDetector")
				clickDetector.Parent = button
				clickDetector.MaxActivationDistance = 32
			end

			local conn = clickDetector.MouseClick:Connect(function(playerWhoClicked: Player)
				-- Pass the correct game instance 'self' to the handler
				Private.onButtonClick(self, button, playerWhoClicked)
			end)
			table.insert(self.connections, conn)
		end
	end
	print("Board Initialized:", self.board:GetFullName(), "Waiting for first player...")
end

-- ==================================
--      PUBLIC INTERFACE START
-- ==================================

--[[* Creates a new TicTacToe game instance *]]
-- Corrected return type annotation
function Shared.new(board: Model): TicTacToeGame
	local self = setmetatable({}, Shared) :: any -- Cast to 'any' temporarily for setup

	-- Initialize properties defined in TicTacToeGame type
	self.board = board
	self.gameOver = true
	self.movesMade = 0
	self.playerX = nil
	self.connections = {}
	self.xModelReference = ReplicatedStorage:FindFirstChild("XModel") :: Model?
	self.oModelReference = ReplicatedStorage:FindFirstChild("OModel") :: Model?
	self.onButtonChanged = Instance.new("BindableEvent")
	self.onGameEnd = Instance.new("BindableEvent")

	assert(self.oModelReference, "TicTacToeLogic: OModel not found in ReplicatedStorage!")
	assert(self.xModelReference, "TicTacToeLogic: XModel not found in ReplicatedStorage!")

	print("TicTacToe Instance Created for board:", board:GetFullName())

	-- Now that 'self' is fully formed according to the type, cast it back
	return self :: TicTacToeGame
end

--[[* Initializes the game board for a new game *]]
-- Corrected type annotation for 'self'
function Shared:init()
	Private.InitializeBoard(self)
end

--[[* Cleans up the game instance, disconnecting events and removing visuals *]]
-- Corrected type annotation for 'self'
function Shared:destroy()
	print("Destroying TicTacToe Instance for board:", self.board and self.board:GetFullName() or "N/A")
	if self.board then
		for _, button in ipairs(self.board:GetChildren()) do
			if button:IsA("BasePart") and button:GetAttribute("Column") and button:GetAttribute("Row") then
				Private.removeVisualModel(button)
			end
		end
	end

	if self.connections then
		for _, conn in pairs(self.connections) do
			conn:Disconnect()
		end
		table.clear(self.connections)
	end

	-- Destroy BindableEvents specific to this instance
	-- Check they exist before destroying as 'destroy' might be called multiple times
	if self.onButtonChanged then
		self.onButtonChanged:Destroy()
		self.onButtonChanged = nil -- Help GC by removing reference
	end
	if self.onGameEnd then
		self.onGameEnd:Destroy()
		self.onGameEnd = nil -- Help GC by removing reference
	end

	-- Clear references to allow garbage collection
	self.board = nil
	self.playerX = nil
	self.xModelReference = nil
	self.oModelReference = nil
	self.connections = nil
	-- Don't setmetatable(self, nil) here, it can cause issues if references still exist.
	-- Let GC handle the table itself once all references are gone.

	print("TicTacToe Instance Destroyed")
end

return Shared -- Return the table containing the public methods (new, init, destroy)
