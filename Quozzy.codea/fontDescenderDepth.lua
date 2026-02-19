function drawTextIgnoringDescendersWithBottomAt(str,x,bottomY)
    local d = fontMetrics().descent    
    pushStyle()
    textMode(CORNER); 
    textAlign(LEFT)
    text(str,x,bottomY-d)
    popStyle()
end