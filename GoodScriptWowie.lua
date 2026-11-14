
-- Discord: abakainasuit
-- Github: BobbyG555
-- Roblox: Witherbonbon55

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- This gets the arena because its size and position are used when spawning food
local Arena: BasePart = workspace:WaitForChild("BlobArena") :: BasePart

-- These settings control how much food can exist and how quickly missing food comes back
local Max_food: number = 150
local Food_respawn: number = 0.3
local Food_count: number = 0

-- This controls the chance for special food
local Golden_chance: number = 2

local Starting_mass: number = 10
local Death_loss: number = 0.25

-- Keeping food inside its own folder makes it easier to find and clean up later
local Food_folder = Instance.new("Folder")
Food_folder.Name = "BlobFood"
Food_folder.Parent = workspace

type FoodInfo = {
    worth: number,
    size: number,
    color: Color3,
    chance: number
}

type FoodData = {
    worth: number,
    collected: boolean
}

-- Each food type has its own chance so common food appears more often than valuable food
local Food_types: {FoodInfo} = {
    {
        worth = 1,
        size = 0.7,
        color = Color3.fromRGB(255, 220, 70),
        chance = 55
    },

    {
        worth = 3,
        size = 1,
        color = Color3.fromRGB(70, 255, 120),
        chance = 30
    },

    {
        worth = 5,
        size = 1.3,
        color = Color3.fromRGB(255, 80, 180),
        chance = 15
    }
}

-- This stores information for each food part so collection and cleanup can access the same data
local Food_data: {[BasePart]: FoodData} = {}

-- This checks the arena before other functions try to use its CFrame or Size
local function Arena_exists(): boolean
    return Arena.Parent ~= nil
end

-- This creates a random position using the arena's local space so rotated arenas still work
local function Random_pos(): Vector3
    local Arena_size: Vector3 = Arena.Size

    local X: number = math.random(
        math.ceil(-Arena_size.X / 2 + 5),
        math.floor(Arena_size.X / 2 - 5)
    )

    local Z: number = math.random(
        math.ceil(-Arena_size.Z / 2 + 5),
        math.floor(Arena_size.Z / 2 - 5)
    )

    -- This places food slightly above the arena floor so it does not spawn inside the ground
    local Local_position: Vector3 = Vector3.new(
        X,
        Arena_size.Y / 2 + 1.5,
        Z
    )

    return Arena.CFrame:PointToWorldSpace(Local_position)
end

-- This rolls between 1 and 100 and uses the chance values to choose a food type
local function Pick_food(): FoodInfo
    local Roll: number = math.random(1, 100)
    local Total: number = 0

    for _, Info: FoodInfo in ipairs(Food_types) do
        Total += Info.chance

        if Roll <= Total then
            return Info
        end
    end

    return Food_types[1]
end

-- This checks which player touched the food and ignores anything that is not a living blob character
local function Get_player(Hit: BasePart): Player?
    local Character: Model? = Hit:FindFirstAncestorOfClass("Model")

    if not Character then
        return nil
    end

    local Player: Player? = Players:GetPlayerFromCharacter(Character)
    if not Player then
        return nil
    end

    local Humanoid: Humanoid? = Character:FindFirstChildOfClass("Humanoid")

    if not Humanoid or Humanoid.Health <= 0 then
        return nil
    end

    if not Character:FindFirstChild("BlobBody") then
        return nil
    end

    return Player
end

-- This makes new food grow into its selected size instead of appearing at full size immediately
local function Play_appear(Food: BasePart, Size: number): ()
    local Appear: Tween = TweenService:Create(
        Food,
        TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Size = Vector3.new(Size, Size, Size)
        }
    )

    Appear:Play()
end

-- This adds the light and particles to golden food so it is easier to notice in the arena
local function Add_golden_effects(Food: BasePart, Color: Color3): ()
    local Light = Instance.new("PointLight")
    Light.Color = Color
    Light.Brightness = 2
    Light.Range = 12
    Light.Parent = Food

    local Particles = Instance.new("ParticleEmitter")
    Particles.Rate = 8
    Particles.Lifetime = NumberRange.new(0.4, 0.8)
    Particles.Speed = NumberRange.new(1, 3)
    Particles.SpreadAngle = Vector2.new(180, 180)
    Particles.Color = ColorSequence.new(Color)
    Particles.Parent = Food

    -- This changes the brightness back and forth while the golden food still exists
    task.spawn(function()
        while Food.Parent and Food_data[Food] do
            local Up: Tween = TweenService:Create(
                Light,
                TweenInfo.new(0.5),
                {Brightness = 4}
            )

            Up:Play()
            Up.Completed:Wait()

            if not Food.Parent or not Food_data[Food] then
                break
            end

            local Down: Tween = TweenService:Create(
                Light,
                TweenInfo.new(0.5),
                {Brightness = 1}
            )

            Down:Play()
            Down.Completed:Wait()
        end
    end)
end

-- This updates the Mass attribute which is also used by the leaderstats system
local function Add_mass(Player: Player, Amount: number): ()
    local Old_mass: number = Player:GetAttribute("Mass") or Starting_mass
    Player:SetAttribute("Mass", Old_mass + Amount)
end

-- This counts how many pieces of food the player has collected
local function Add_food_stat(Player: Player): ()
    local Old_food: number = Player:GetAttribute("FoodEaten") or 0
    Player:SetAttribute("FoodEaten", Old_food + 1)
end

-- This shrinks collected food before destroying it so the collection has a small animation
local function Remove_food(Food: BasePart): ()
    if not Food.Parent then
        return
    end

    Food.CanTouch = false
    Food.CanQuery = false

    local Disappear: Tween = TweenService:Create(
        Food,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            Size = Vector3.new(0.1, 0.1, 0.1),
            Transparency = 1
        }
    )

    Disappear:Play()
    Disappear.Completed:Wait()

    if Food.Parent then
        Food:Destroy()
    end
end

-- This handles the reward so the same food cannot be collected by multiple body parts
local function Collect_food(Food: BasePart, Hit: BasePart): ()
    local Data: FoodData? = Food_data[Food]

    if not Data or Data.collected then
        return
    end

    local Player: Player? = Get_player(Hit)
    if not Player then
        return
    end

    -- This marks the food as collected before giving rewards to stop duplicate touch events
    Data.collected = true
    Food.CanTouch = false

    Add_mass(Player, Data.worth)
    Add_food_stat(Player)

    Remove_food(Food)
end

-- This connects the touch event after the food has been created and its data has been saved
local function Connect_food(Food: BasePart): ()
    Food.Touched:Connect(function(Hit: BasePart)
        if not Food.Parent then
            return
        end

        Collect_food(Food, Hit)
    end)
end

-- This creates the actual food part and sets the properties needed for collection
local function Create_food_part(
    Position: Vector3,
    Size: number,
    Color: Color3,
    Is_golden: boolean
): Part

    local Food = Instance.new("Part")
    Food.Name = Is_golden and "GoldenFood" or "Food"
    Food.Shape = Enum.PartType.Ball
    Food.Size = Vector3.new(0.1, 0.1, 0.1)
    Food.CFrame = CFrame.new(Position)

    -- Anchored food does not need physics movement because TweenService handles its movement
    Food.Anchored = true
    Food.CanCollide = false
    Food.CanTouch = true
    Food.CanQuery = true
    Food.CastShadow = false

    Food.Material = Enum.Material.Neon
    Food.Color = Color

    Food.Parent = Food_folder
    CollectionService:AddTag(Food, "BlobFood")

    return Food
end

-- This chooses the food settings and creates the part if the arena has room for more food
local function Spawn_food(): boolean
    if not Arena_exists() or Food_count >= Max_food then
        return false
    end

    local Food_info: FoodInfo = Pick_food()
    local Is_golden: boolean = math.random(1, 100) <= Golden_chance

    local Worth: number = Food_info.worth
    local Size: number = Food_info.size
    local Color: Color3 = Food_info.color

    -- Golden food overrides the normal values so it gives a bigger reward
    if Is_golden then
        Worth = 25
        Size = 1.8
        Color = Color3.fromRGB(255, 190, 0)
    end

    local Position: Vector3 = Random_pos()

    local Food: Part = Create_food_part(
        Position,
        Size,
        Color,
        Is_golden
    )

    -- This saves the reward and position before any touch or movement events can use the food
    Food_data[Food] = {
        worth = Worth,
        collected = false
    }

    Food_count += 1

    Play_appear(Food, Size)

    if Is_golden then
        Add_golden_effects(Food, Color)
    end

    Connect_food(Food)

    return true
end

-- This clears the saved data and updates the count whenever a food part is removed
Food_folder.ChildRemoved:Connect(function(Child: Instance)
    if not Child:IsA("BasePart") then
        return
    end

    Food_data[Child] = nil
    Food_count = math.max(0, Food_count - 1)
end)

-- This creates the Mass leaderstat and keeps it updated whenever the player attribute changes
local function Setup_leaderstats(Player: Player): ()
    Player:SetAttribute("Mass", Starting_mass)
    Player:SetAttribute("FoodEaten", 0)

    local Stats = Instance.new("Folder")
    Stats.Name = "leaderstats"
    Stats.Parent = Player

    local Mass = Instance.new("IntValue")
    Mass.Name = "Mass"
    Mass.Value = Starting_mass
    Mass.Parent = Stats

    Player:GetAttributeChangedSignal("Mass"):Connect(function()
        local Current_mass: number = Player:GetAttribute("Mass") or Starting_mass
        Mass.Value = math.floor(Current_mass)
    end)
end

-- This removes a percentage of mass after death but does not let it go below the starting amount
local function Handle_death(Player: Player): ()
    local Current_mass: number = Player:GetAttribute("Mass") or Starting_mass

    if Current_mass <= Starting_mass then
        return
    end

    local Lost: number = math.floor(Current_mass * Death_loss)
    local New_mass: number = math.max(Starting_mass, Current_mass - Lost)

    Player:SetAttribute("Mass", New_mass)
end

-- This connects the death event whenever a player gets a new character
local function Setup_character(Player: Player, Character: Model): ()
    local Humanoid: Humanoid = Character:WaitForChild("Humanoid") :: Humanoid

    Humanoid.Died:Connect(function()
        Handle_death(Player)
    end)
end

-- This prepares the player's stats and character events when they join
local function Setup_player(Player: Player): ()
    Setup_leaderstats(Player)

    Player.CharacterAdded:Connect(function(Character: Model)
        Setup_character(Player, Character)
    end)

    -- This also handles players who already have a character when the script starts
    if Player.Character then
        Setup_character(Player, Player.Character)
    end
end

Players.PlayerAdded:Connect(Setup_player)

-- This sets up players already inside the server so they are not missed
for _, Player: Player in ipairs(Players:GetPlayers()) do
    Setup_player(Player)
end

-- This creates the starting food in small batches so the server does not spawn everything at once
local function Spawn_starting_food(): ()
    for Index: number = 1, 80 do
        if Food_count >= Max_food then
            break
        end

        Spawn_food()
        task.wait(0.01)
    end
end

-- This keeps spawning replacement food whenever players collect enough to go below the limit
local function Start_food_respawn(): ()
    task.spawn(function()
        while Arena_exists() do
            task.wait(Food_respawn)

            if Food_count < Max_food then
                Spawn_food()
            end
        end
    end)
end

-- This clears remaining food if the arena gets removed while the game is running
local function Start_arena_check(): ()
    task.spawn(function()
        while task.wait(5) do
            if not Arena_exists() then
                Food_folder:ClearAllChildren()
                break
            end
        end
    end)
end

-- This starts each system after all the functions and events have been set up
local function Start_system(): ()
    Spawn_starting_food()

    Start_food_respawn()
    Start_arena_check()
end

Start_system()