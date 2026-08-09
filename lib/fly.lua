local Library = {}

function Library.CreateBar(parent)
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Parent = parent
    ScreenGui.Enabled = false

    local Frame = Instance.new("Frame")
    Frame.Parent = ScreenGui
    Frame.AnchorPoint = Vector2.new(0.5, 0.5)
    Frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Frame.BackgroundTransparency = 0.5
    Frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
    Frame.BorderSizePixel = 0
    Frame.Position = UDim2.new(0.5, 0, 0.8, 0)
    Frame.Size = UDim2.new(0.277, 0, 0, 20)

    local SecondLeft = Instance.new("TextLabel")
    SecondLeft.Name = "SecondLeft"
    SecondLeft.Parent = Frame
    SecondLeft.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    SecondLeft.BackgroundTransparency = 1
    SecondLeft.BorderColor3 = Color3.fromRGB(0, 0, 0)
    SecondLeft.BorderSizePixel = 0
    SecondLeft.Position = UDim2.new(0.5, 0, 0.4, 0)
    SecondLeft.AnchorPoint = Vector2.new(0.5, 0.5)
    SecondLeft.Size = UDim2.new(0, 340, 0, 19)
    SecondLeft.Font = Enum.Font.Gotham
    SecondLeft.Text = "0s"
    SecondLeft.TextColor3 = Color3.fromRGB(0, 0, 0)
    SecondLeft.TextSize = 20
    SecondLeft.ZIndex = 2

    local Bar = Instance.new("Frame")
    Bar.Name = "Bar"
    Bar.Parent = Frame
    Bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Bar.BorderColor3 = Color3.fromRGB(0, 0, 0)
    Bar.BorderSizePixel = 0
    Bar.ZIndex = 1
    Bar.Visible = false
        
    return {
        ScreenGui = ScreenGui,
        Frame = Frame,
        SecondLeft = SecondLeft,
        Bar = Bar
    }
end

return Library