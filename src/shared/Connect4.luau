local Shared = {}
local Private = {}

Shared.__index = Shared

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

function Private.OnTrigger(playerWhoTriggered, self)
	if self.player1 == nil then
		self.player1 = playerWhoTriggered
	elseif self.player2 == nil then
		self.player2 = playerWhoTriggered
	else
		warn("Already max players on board " .. self.board:GetFullName())
		return
	end
end

function Private.MakePrompts(self)
	if self.board:FindFirstChildOfClass("ProximityPrompt") then
		return
	end

	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Parent = self.board.PrimaryPart
	Prompt.Name = "ProximityPrompt"

	local TriggerConnection = Prompt.Triggered:Connect(function(playerWhoTriggered)
		Private.OnTrigger(playerWhoTriggered, self)
	end)

	table.insert(self.connections, TriggerConnection)
end

function Private.CreateGrid(self)
	self.grid = {}
	for r = 1 , self.maxRows do
		self.grid[r] = {}
		for c = 1 , self.maxCols do
			self.grid[r][c] = 0
		end
	end
end

function Private.InitializeBoard(self)
	print("Initializing board:", self.board:GetFullName())
	
	self.gameOver = false
	self.movesMade = 0
	self.player1 = nil
	self.player2 = nil
	self.maxRows, self.maxCols = Private.GetMaxRowsAndCols(self)
	Private.CreateGrid(self)
	print(self.grid)

	if self.connections then
		for _, conn in self.connections do
			conn:Disconnect()
		end
		table.clear(self.connections)
	else
		self.connections = {}
	end
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
	self.onButtonChanged = Instance.new("BindableEvent")
	self.onGameEnd = Instance.new("BindableEvent")

	return self
end
function Shared:init()
	Private.InitializeBoard(self)
end
return Shared