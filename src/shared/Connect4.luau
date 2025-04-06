local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Or wherever you store piece templates

--[[
    Assumptions:
    1. 'board' Model contains BaseParts with "Row" (Int) and "Column" (Int) attributes.
    2. ClickDetectors will be automatically added to parts with Row/Col attributes if missing.
    3. Optional: Piece models ('RedPiece', 'YellowPiece') are in ReplicatedStorage for cloning.
    4. Optional: A PrimaryPart is set for the 'board' model for the ProximityPrompt.
]]

-- Configuration (Customize as needed)
local USE_PIECE_MODELS = true -- Set to false to just change part colors
local PLAYER1_COLOR = BrickColor.new("Bright red")
local PLAYER2_COLOR = BrickColor.new("Bright yellow")
local DEFAULT_COLOR = BrickColor.new("Medium stone grey")
local RESET_DELAY = 5 -- Seconds before the board resets after a game ends
local CLICK_DETECTOR_NAME = "BoardClickDetector" -- Consistent name for created detectors

-- Shared and Private tables
local Shared = {}
local Private = {}
Shared.__index = Shared

--[[-------------------------
     PRIVATE HELPER FUNCTIONS
---------------------------]]

-- Finds the BasePart corresponding to a specific row and column
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

-- Gets the board dimensions by finding max row and column attributes
function Private.GetMaxRowsAndCols(self)
	local maxRows = 0
	local maxCols = 0
	for _, button in self.board:GetChildren() do
		if button:IsA("BasePart") then
			local row = button:GetAttribute("Row")
			local col = button:GetAttribute("Column")
			if typeof(row) == "number" and typeof(col) == "number" then
				maxRows = math.max(maxRows, row)
				maxCols = math.max(maxCols, col)
			else
				warn("Part " .. button:GetFullName() .. " is missing Row/Column attributes or they are not numbers.")
			end
		end
	end
	return maxRows, maxCols
end

-- Resets the visual appearance of all board slots
function Private.ResetBoardVisuals(self)
	for _, button in self.board:GetChildren() do
		if button:IsA("BasePart") and button:GetAttribute("Row") and button:GetAttribute("Column") then
			for _, child in button:GetChildren() do
				if child:GetAttribute("IsGamePiece") then
					child:Destroy()
				end
			end
			button.BrickColor = DEFAULT_COLOR
			button.Material = Enum.Material.Plastic
		end
	end
end

-- Creates the internal grid representation
function Private.CreateGrid(self)
	self.grid = {}
	for r = 1, self.maxRows do
		self.grid[r] = {}
		for c = 1, self.maxCols do
			self.grid[r][c] = 0 -- 0: empty, 1: player1, 2: player2
		end
	end
end

-- Handles player joining via ProximityPrompt
function Private.OnTrigger(playerWhoTriggered: Player, self)
	if self.gameOver == false and (self.player1 == playerWhoTriggered or self.player2 == playerWhoTriggered) then
		warn(playerWhoTriggered.Name .. " is already playing on board " .. self.board:GetFullName())
		return
	end

	if not self.player1 then
		self.player1 = playerWhoTriggered
		print(playerWhoTriggered.Name .. " joined as Player 1 (Red)")
		self.onPlayerJoined:Fire(playerWhoTriggered, 1) -- Fire event
	elseif not self.player2 then
		self.player2 = playerWhoTriggered
		print(playerWhoTriggered.Name .. " joined as Player 2 (Yellow)")
		self.onPlayerJoined:Fire(playerWhoTriggered, 2) -- Fire event
	else
		warn(
			"Already max players ("
				.. (self.player1 and self.player1.Name or "N/A")
				.. ", "
				.. (self.player2 and self.player2.Name or "N/A")
				.. ") on board "
				.. self.board:GetFullName()
		)
		return
	end

	if self.player1 and self.player2 and self.gameOver == true then
		print("Both players present. Starting new game!")
		Private.StartGame(self)
	elseif self.player1 and self.player2 then
		print("Both players present. Game active.")
	end
end

-- Creates the ProximityPrompt for joining
function Private.MakePrompts(self)
	if not self.board.PrimaryPart then
		warn("Board " .. self.board:GetFullName() .. " needs a PrimaryPart set to create a ProximityPrompt.")
		return
	end

	local existingPrompt = self.board.PrimaryPart:FindFirstChild("JoinGamePrompt")
	if existingPrompt then
		if self.promptConnection then
			self.promptConnection:Disconnect()
		end
	else
		local Prompt = Instance.new("ProximityPrompt")
		Prompt.ObjectText = "Connect 4"
		Prompt.ActionText = "Join Game"
		Prompt.Name = "JoinGamePrompt"
		Prompt.Parent = self.board.PrimaryPart
		Prompt.MaxActivationDistance = 15
		Prompt.RequiresLineOfSight = false
	end

	local Prompt = self.board.PrimaryPart:FindFirstChild("JoinGamePrompt")
	if Prompt then -- Check prompt exists before connecting
		self.promptConnection = Prompt.Triggered:Connect(function(playerWhoTriggered)
			Private.OnTrigger(playerWhoTriggered, self)
		end)
	else
		warn("Failed to find or create JoinGamePrompt on " .. self.board.PrimaryPart:GetFullName())
	end
end

-- Finds the lowest available row in a given column
function Private.FindLowestAvailableRow(self, col)
	for r = self.maxRows, 1, -1 do
		if self.grid[r][col] == 0 then
			return r
		end
	end
	return nil
end

-- Updates the visual appearance of a slot
function Private.UpdateSlotVisual(self, row, col, playerNumber)
	local part = Private.GetPartAt(self, row, col)
	if not part then
		return
	end

	local playerColor = if playerNumber == 1 then PLAYER1_COLOR else PLAYER2_COLOR
	local pieceName = if playerNumber == 1 then "RedPiece" else "YellowPiece"

	if USE_PIECE_MODELS then
		local pieceTemplate = ReplicatedStorage:FindFirstChild(pieceName)
		if pieceTemplate and pieceTemplate:IsA("BasePart") then -- Check template exists and is a part/model
			local newPiece = pieceTemplate:Clone()
			newPiece:SetAttribute("IsGamePiece", true)
			newPiece.Anchored = true -- Ensure pieces don't fall unnecessarily
			newPiece.CanCollide = false -- Avoid physics issues with board
			newPiece.CFrame = part.CFrame
			newPiece.Parent = part -- Parent to the slot for organization
		else
			warn(
				"Piece template '"
					.. pieceName
					.. "' not found or not a valid Part/Model in ReplicatedStorage. Falling back to color change."
			)
			part.BrickColor = playerColor
		end
	else
		part.BrickColor = playerColor
	end
end

-- Checks for a win condition starting from the last placed piece
function Private.CheckWin(self, lastRow, lastCol)
	local player = self.grid[lastRow][lastCol]
	if player == 0 then
		return false
	end

	local directions = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }

	for _, dir in ipairs(directions) do
		local count = 1
		for i = 1, 3 do
			local r = lastRow + dir[1] * i
			local c = lastCol + dir[2] * i
			if r >= 1 and r <= self.maxRows and c >= 1 and c <= self.maxCols and self.grid[r][c] == player then
				count += 1
			else
				break
			end
		end
		for i = 1, 3 do
			local r = lastRow - dir[1] * i
			local c = lastCol - dir[2] * i
			if r >= 1 and r <= self.maxRows and c >= 1 and c <= self.maxCols and self.grid[r][c] == player then
				count += 1
			else
				break
			end
		end
		if count >= 4 then
			return true
		end
	end
	return false
end

-- Checks if the game is a draw (board full)
function Private.CheckDraw(self)
	return self.movesMade >= (self.maxRows * self.maxCols)
end

-- Switches the current player
function Private.SwitchTurn(self)
	self.currentPlayer = if self.currentPlayer == self.player1 then self.player2 else self.player1
	if self.currentPlayer then -- Ensure player didn't leave
		print("Turn: " .. self.currentPlayer.Name)
		self.onTurnChanged:Fire(self.currentPlayer) -- Fire event
	else
		-- Handle case where player might have left during turn switch (unlikely but possible)
		print("Current player is nil after switch, game may be paused.")
		self.gameOver = true
		Private.SetClickDetectorsEnabled(self, false)
	end
end

-- Handles the end of the game
function Private.EndGame(self, winner: Player?)
	self.gameOver = true
	print("---------------- GAME OVER ----------------")
	if winner then
		print(winner.Name .. " wins!")
	else
		print("It's a draw!")
	end
	self.onGameEnd:Fire(winner)

	Private.SetClickDetectorsEnabled(self, false)

	task.delay(RESET_DELAY, function()
		if self and self.board and self.board.Parent then
			print("Resetting board...")
			Private.InitializeBoard(self)
		else
			print("Game object destroyed before reset.")
		end
	end)
end

-- Enables or disables all click detectors associated with the board
function Private.SetClickDetectorsEnabled(self, enabled: boolean)
	for _, detector in ipairs(self.clickDetectors) do
		if detector and detector.Parent then
			detector.MaxActivationDistance = if enabled then 32 else 0
		end
	end
end

-- Handles a player clicking on ANY part with a Column attribute
function Private.OnColumnClicked(playerWhoClicked: Player, column: number, self)
	if self.gameOver then
		print("Game is over. Cannot place piece.")
		return
	end
	if not self.player1 or not self.player2 then
		print("Waiting for two players.")
		return
	end
	if playerWhoClicked ~= self.currentPlayer then
		print("Not your turn, " .. playerWhoClicked.Name)
		return
	end

	local row = Private.FindLowestAvailableRow(self, column)
	if not row then
		print("Column " .. column .. " is full.")
		return
	end

	local playerNumber = if self.currentPlayer == self.player1 then 1 else 2
	self.grid[row][column] = playerNumber
	self.movesMade += 1
	print(self.currentPlayer.Name .. " placed piece at (" .. row .. ", " .. column .. ")")

	Private.UpdateSlotVisual(self, row, column, playerNumber)
	self.onButtonChanged:Fire(row, column, self.currentPlayer)

	if Private.CheckWin(self, row, column) then
		Private.EndGame(self, self.currentPlayer)
	elseif Private.CheckDraw(self) then
		Private.EndGame(self, nil)
	else
		Private.SwitchTurn(self)
	end
end

-- NEW: Sets up click detectors, creating them if they don't exist on parts with Row/Col attributes
function Private.SetupClickDetectors(self)
	-- Clear previous connections and detector references first
	for _, conn in ipairs(self.clickConnections) do
		conn:Disconnect()
	end
	table.clear(self.clickConnections)
	table.clear(self.clickDetectors)

	for _, part in self.board:GetChildren() do
		-- Check if it's a BasePart with the required attributes
		if part:IsA("BasePart") then
			local row = part:GetAttribute("Row")
			local col = part:GetAttribute("Column")

			if typeof(row) == "number" and typeof(col) == "number" then
				-- Attributes found, ensure ClickDetector exists
				local detector = part:FindFirstChild(CLICK_DETECTOR_NAME)
				if not detector then
					-- Create the ClickDetector if it's missing
					detector = Instance.new("ClickDetector")
					detector.Name = CLICK_DETECTOR_NAME
					detector.MaxActivationDistance = 32 -- Default distance, will be controlled by SetClickDetectorsEnabled
					detector.Parent = part
					print("Created ClickDetector for part:", part:GetFullName())
				end

				-- Now that we know detector exists (or we just created it), connect it
				if detector and detector:IsA("ClickDetector") then -- Double check it's the correct type
					table.insert(self.clickDetectors, detector) -- Store detector instance
					local connection = detector.MouseClick:Connect(function(playerWhoClicked)
						-- Use the 'col' variable captured when iterating through parts
						Private.OnColumnClicked(playerWhoClicked, col, self)
					end)
					table.insert(self.clickConnections, connection) -- Store connection for cleanup
				end
			end
		end
	end
	Private.SetClickDetectorsEnabled(self, false) -- Initially disable until game starts
end

-- Initializes or resets the game board state
function Private.InitializeBoard(self)
	print("Initializing board:", self.board:GetFullName())
	self.gameOver = true
	self.movesMade = 0
	self.player1 = nil
	self.player2 = nil
	self.currentPlayer = nil

	self.maxRows, self.maxCols = Private.GetMaxRowsAndCols(self)
	if self.maxRows == 0 or self.maxCols == 0 then
		error(
			"Board "
				.. self.board:GetFullName()
				.. " has invalid dimensions (0 rows or 0 columns). Check part attributes."
		)
		return
	end
	print("Board dimensions: " .. self.maxRows .. " rows, " .. self.maxCols .. " columns.")

	Private.CreateGrid(self)
	Private.ResetBoardVisuals(self)

	-- Manage connections (clear old ones before setting up new)
	if self.clickConnections then
		for _, conn in ipairs(self.clickConnections) do
			conn:Disconnect()
		end
		table.clear(self.clickConnections)
	else
		self.clickConnections = {}
	end
	if not self.clickDetectors then
		self.clickDetectors = {}
	end

	-- Setup interaction - This will now ALSO create detectors if needed
	Private.SetupClickDetectors(self)
	Private.MakePrompts(self)

	print("Board initialized. Waiting for players...")
end

-- Starts the actual gameplay once two players are ready
function Private.StartGame(self)
	if not self.player1 or not self.player2 then
		warn("Attempted to start game without two players.")
		return
	end

	print("Starting game between: " .. self.player1.Name .. " (P1) and " .. self.player2.Name .. " (P2)")
	self.gameOver = false
	self.movesMade = 0
	self.currentPlayer = self.player1

	Private.SetClickDetectorsEnabled(self, true) -- Enable clicks now that game has started
	if self.currentPlayer then -- Check player didn't leave instantly
		print("Turn: " .. self.currentPlayer.Name)
		self.onTurnChanged:Fire(self.currentPlayer) -- Fire event
	end
end

-- Handles player removal/leaving
function Private.OnPlayerRemoving(player: Player, self)
	print(player.Name .. " is leaving.")
	local wasPlaying = false

	if self.player1 == player then
		self.player1 = nil
		wasPlaying = true
		print("Player 1 slot open.")
	elseif self.player2 == player then -- Use elseif to avoid double processing if player somehow filled both slots
		self.player2 = nil
		wasPlaying = true
		print("Player 2 slot open.")
	end

	if wasPlaying and not self.gameOver then
		print("A player left mid-game. Game paused.")
		self.gameOver = true
		self.currentPlayer = nil -- No current turn
		Private.SetClickDetectorsEnabled(self, false)
		-- Optional: Announce winner by default?
		-- if remainingPlayer then
		--     print(remainingPlayer.Name .. " wins by default!")
		--     self.onGameEnd:Fire(remainingPlayer) -- Fire event with winner
		-- end
		-- Resetting immediately might be better UX than leaving a half-finished game
		print("Scheduling reset due to player leaving mid-game.")
		task.delay(RESET_DELAY, function()
			if self and self.board and self.board.Parent then
				Private.InitializeBoard(self)
			end
		end)
	elseif wasPlaying and self.gameOver then
		print("Player left after game ended.")
		-- Game is already over, reset is likely scheduled or happened.
		-- If no players left, ensure prompt is available.
		if not self.player1 and not self.player2 then
			Private.MakePrompts(self)
		end
	end

	-- Ensure prompt is available if a slot opened up
	if not self.player1 or not self.player2 then
		Private.MakePrompts(self)
	end
end

--[[-------------------------
     SHARED / PUBLIC METHODS
---------------------------]]

function Shared.new(board: Model)
	local self = setmetatable({}, Shared)
	self.board = board
	self.grid = {}
	self.maxRows, self.maxCols = 0, 0
	self.gameOver = true
	self.movesMade = 0
	self.player1= nil
	self.player2 = nil
	self.currentPlayer = nil
	self.clickConnections, self.clickDetectors = {}, {}
	self.promptConnection, self.playerRemovingConnection = nil, nil
	-- Removed self.connections as it seemed redundant

	self.onButtonChanged = Instance.new("BindableEvent")
	self.onGameEnd = Instance.new("BindableEvent")
	self.onPlayerJoined = Instance.new("BindableEvent")
	self.onTurnChanged = Instance.new("BindableEvent")

	--Private.InitializeBoard(self) -- This now also ensures ClickDetectors exist

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		Private.OnPlayerRemoving(player, self)
	end)

	print("Connect Four game object created for board: " .. board:GetFullName())
	return self
end

function Shared:init()
	print("Initializing Connect Four game object for board: " .. (self.board and self.board:GetFullName() or "nil"))
	Private.InitializeBoard(self)
end
-- Public method to reset the game manually if needed
function Shared:ResetGame()
	print("Manual game reset requested.")
	-- Add checks? e.g., don't reset if game active? Or allow force reset?
	Private.InitializeBoard(self)
end

-- Public method to clean up connections and events when the game is destroyed
function Shared:Destroy()
	print("Destroying Connect Four game object for: " .. (self.board and self.board:GetFullName() or "nil"))
	self.gameOver = true -- Prevent further actions

	if self.promptConnection then
		self.promptConnection:Disconnect()
	end
	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
	end

	for _, conn in ipairs(self.clickConnections) do
		conn:Disconnect()
	end
	table.clear(self.clickConnections)
	table.clear(self.clickDetectors)

	-- Destroy BindableEvents safely
	if self.onButtonChanged then
		self.onButtonChanged:Destroy()
	end
	if self.onGameEnd then
		self.onGameEnd:Destroy()
	end
	if self.onPlayerJoined then
		self.onPlayerJoined:Destroy()
	end
	if self.onTurnChanged then
		self.onTurnChanged:Destroy()
	end

	-- Clear references to help GC
	self.board = nil
	self.grid = nil
	self.player1 = nil
	self.player2 = nil
	self.currentPlayer = nil
	self.promptConnection = nil
	self.playerRemovingConnection = nil
	self.clickConnections = nil
	self.clickDetectors = nil
	self.onButtonChanged = nil
	self.onGameEnd = nil
	self.onPlayerJoined = nil
	self.onTurnChanged = nil

	setmetatable(self, nil) -- Remove metatable
end

return Shared
