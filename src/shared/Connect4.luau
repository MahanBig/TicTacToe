local Shared = {}
local Private = {}

Shared.__index = Shared

-- Constants
local DEFAULT_COLOR = Color3.new(1, 1, 1)
local PLAYER1_COLOR = Color3.new(1, 0.0, 0.0)
local PLAYER2_COLOR = Color3.new(1, 0.949019, 0.509803)

-- Private functions

function Private.GetMaxRowsAndCols(self)
	local maxRows = 0
	local maxCols = 0

	for _, button in self.board:GetChildren() do
		if button:IsA("BasePart") and button:GetAttribute("Row") and button:GetAttribute("Column") then
			local row = button:GetAttribute("Row")
			local col = button:GetAttribute("Column")

			if row > maxRows then
				maxRows = row
			end

			if col > maxCols then
				maxCols = col
			end
		end
	end

	return maxRows, maxCols
end

function Private.GetPartAt(self, row, col)
	for _, button in self.board:GetChildren() do
		if button:IsA("BasePart") then
			local partRow = button:GetAttribute("Row")
			local partCol = button:GetAttribute("Column")
			if partRow == row and partCol == col then
				return button
			end
		end
	end
	return nil
end

-- Add this inside Private functions section

function Private.PlacePiece(self, column)
	if self.gameOver then
		return
	end

	local currentPlayer = self.currentPlayer
	local playerNum = (currentPlayer == self.player1) and 1 or 2

	for row = self.maxRows, 1, -1 do
		if self.grid[row][column] == 0 then
			self.grid[row][column] = playerNum

			local part = Private.GetPartAt(self, row, column)
			if part then
				local color = (playerNum == 1) and PLAYER1_COLOR or PLAYER2_COLOR
				part.Color = color
			end

			self.movesMade += 1

			if Private.CheckWin(self, row, column, playerNum) then
				self.gameOver = true
				print(currentPlayer.Name .. " wins!")
				task.delay(5, function()
					print("Restarting game...")
					Private.InitializeBoard(self)
				end)
				return
			elseif self.movesMade >= self.maxRows * self.maxCols then
				self.gameOver = true
				print("It's a draw!")
				task.delay(5, function()
					print("Restarting game...")
					Private.InitializeBoard(self)
				end)
				return
			else
				self.currentPlayer = (currentPlayer == self.player1) and self.player2 or self.player1
				print("Now it's " .. self.currentPlayer.Name .. "'s turn.")
			end
			break
		end
	end
end

function Private.CheckDirection(self, row, col, dRow, dCol, playerNum)
	local count = 1

	for direction = -1, 1, 2 do
		local r, c = row + direction * dRow, col + direction * dCol
		while r >= 1 and r <= self.maxRows and c >= 1 and c <= self.maxCols and self.grid[r][c] == playerNum do
			count += 1
			r += direction * dRow
			c += direction * dCol
		end
	end

	return count >= 4
end

function Private.CheckWin(self, row, col, playerNum)
	return Private.CheckDirection(self, row, col, 0, 1, playerNum) -- Horizontal
		or Private.CheckDirection(self, row, col, 1, 0, playerNum) -- Vertical
		or Private.CheckDirection(self, row, col, 1, 1, playerNum) -- Diagonal \
		or Private.CheckDirection(self, row, col, 1, -1, playerNum) -- Diagonal /
end

function Private.StartGame(self)
	Private.CreateGrid(self)

	for _, part in self.board:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = DEFAULT_COLOR
		end
	end

	self.movesMade = 0
	self.gameOver = false
	self.currentPlayer = self.player1

	for _, part in self.board:GetChildren() do
		if part:IsA("BasePart") then
			local existingCD = part:FindFirstChildOfClass("ClickDetector")
			if existingCD then
				existingCD:Destroy()
			end

			local col = part:GetAttribute("Column")
			local clickDetector = Instance.new("ClickDetector")
			clickDetector.MaxActivationDistance = 32
			clickDetector.Parent = part

			local connection = clickDetector.MouseClick:Connect(function(player)
				if player == self.currentPlayer then
					Private.PlacePiece(self, col)
				end
			end)

			table.insert(self.connections, connection)
		end
	end

	print("Game started. " .. self.currentPlayer.Name .. "'s turn.")
end

function Private.OnTrigger(playerWhoTriggered: Player, self)
	if self.gameOver == false and (self.player1 == playerWhoTriggered or self.player2 == playerWhoTriggered) then
		warn(playerWhoTriggered.Name .. " is already playing on board " .. self.board:GetFullName())
		return
	end

	if not self.player1 then
		self.player1 = playerWhoTriggered
		self.prompt.ActionText = "(1/2) Join game"
		print(playerWhoTriggered.Name .. " joined as Player 1 (Red)")
	elseif not self.player2 then
		self.player2 = playerWhoTriggered
		print(playerWhoTriggered.Name .. " joined as Player 2 (Yellow)")
	else
		warn("Already max player")
		return
	end

	if self.player1 and self.player2 and self.gameOver == true then
		print("Both players present. Starting new game!")
		Private.StartGame(self)
		local primary = self.board.PrimaryPart
		if not primary then
			return
		end

		if self.prompt then
			self.prompt:Destroy()
		end
	elseif self.player1 and self.player2 then
		print("Both players present. Game active.")
	end
end

function Private.MakePrompts(self)
	local primary = self.board.PrimaryPart
	if not primary then
		return
	end

	if self.prompt then
		self.prompt:Destroy()
	end

	self.prompt = Instance.new("ProximityPrompt")
	self.prompt.Name = "ProximityPrompt"
	self.prompt.ActionText = self.player1 and self.player2 and "Play Again?" or "Join Game"
	self.prompt.ObjectText = "Connect 4"
	self.prompt.RequiresLineOfSight = false
	self.prompt.MaxActivationDistance = 20
	self.prompt.Parent = primary

	local TriggerConnection = self.prompt.Triggered:Connect(function(playerWhoTriggered)
		Private.OnTrigger(playerWhoTriggered, self)
	end)

	table.insert(self.connections, TriggerConnection)
end

function Private.CreateGrid(self)
	self.grid = {}
	for r = 1, self.maxRows do
		self.grid[r] = {}
		for c = 1, self.maxCols do
			self.grid[r][c] = 0
		end
	end
end

function Private.addConnectionsTable(self)
	if self.connections then
		for _, conn in self.connections do
			conn:Disconnect()
		end
		table.clear(self.connections)
	else
		self.connections = {}
	end
end

function Private.ResetBoard(self)
	print("Resetting board for new game")

	self.movesMade = 0
	self.gameOver = true
	self.maxRows, self.maxCols = Private.GetMaxRowsAndCols(self)
	Private.CreateGrid(self)

	-- Clear board visuals
	for _, part in self.board:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = Color3.fromRGB(255, 255, 255)
		end
	end

	-- Clean up connections and click detectors
	Private.addConnectionsTable(self)
	for _, part in self.board:GetChildren() do
		local cd = part:FindFirstChildOfClass("ClickDetector")
		if cd then
			cd:Destroy()
		end
	end
end

function Private.InitializeBoard(self)
	print("Initializing board:", self.board:GetFullName())

	self.player1 = nil
	self.player2 = nil
	Private.ResetBoard(self)
	Private.MakePrompts(self)
end

-- Public (Shared) constructor

function Shared.new(board: Model)
	local self = setmetatable({}, Shared)

	self.board = board
	self.gameOver = false
	self.movesMade = 0
	self.player1 = nil
	self.player2 = nil
	self.connections = {}

	return self
end
function Shared:init()
	Private.InitializeBoard(self)
end
return Shared
