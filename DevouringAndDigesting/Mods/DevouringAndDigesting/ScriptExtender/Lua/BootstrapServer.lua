StatPaths = {
    "Public/DevouringAndDigesting/Stats/Generated/Data/Armor.txt",
    "Public/DevouringAndDigesting/Stats/Generated/Data/Potions.txt",
    "Public/DevouringAndDigesting/Stats/Generated/Data/Spell_Vore.txt",
    "Public/DevouringAndDigesting/Stats/Generated/Data/Items.txt",
}

Ext.Require("Utils/Utils.lua")
Ext.Require("Utils/VoreUtils.lua")

PersistentVars = {}

---Triggers on spell cast.
---@param caster CHARACTER
---@param spell string
---@param spellType string?
---@param spellElement string? Like fire, lightning, etc I think.
---@param storyActionID integer?
function SP_SpellCast(caster, spell, spellType, spellElement, storyActionID)
    -- Format of Regurgitate spells will always be 'SP_Regurgitate_' (which is 15 characters)
    -- followed by either the GUIDSTRING of the prey, or 'All.' Probably possible to add some sort
    -- of extra data to the custom spell, but this is way easier.
    if string.sub(spell, 0, 15) == 'SP_Regurgitate_' then
        -- grabs the GUIDSTRING of the prey, or the string 'All' if we're regurgitating everything
        local prey = string.sub(spell, 16)
        SP_RegurgitatePrey(caster, prey, spell)
        PersistentVars['PredPreyTable'] = SP_Deepcopy(PredPreyTable)
    elseif spell == "SP_Move_Prey_To_Me" then
        SP_TelePreyToPred(caster)
    end
end

---Triggers when a spell is cast with a target.
---@param caster CHARACTER
---@param target CHARACTER
---@param spell string
---@param spellType string?
---@param spellElement string? Like fire, lightning, etc I think.
---@param storyActionID integer?
function SP_OnSpellCastTarget(caster, target, spell, spellType, spellElement, storyActionID)
    if string.find(spell, "Vore") ~= nil and Osi.HasActiveStatus(target, "SP_Inedible") == 0 then
        if (PredPreyTable[caster] ~= nil) then
            _P(SP_GetDisplayNameFromGUID(caster) .. " is already a pred; Nested Vore has not been implemented yet!")
            return
        end
        if spell == 'SP_Target_Vore_Endo' then
            _P('Endo Vore')
            if SP_CanFitPrey(caster, target) then
                SP_DelayCallTicks(5, function()
                    Osi.ApplyStatus(target, "SP_Swallowed_Endo", -1, 1, caster)
                    Osi.ApplyStatus(caster, "SP_Stuffed", 1 * 6, 1, caster)
                    SP_FillPredPreyTable(caster, target, 'SP_Target_Vore_Endo')
                end)
            end
        end
        if spell == 'SP_Target_Vore_Lethal' then
            _P('Lethal Vore')
            if SP_CanFitPrey(caster, target) then
                SP_DelayCallTicks(5, function()
                    SP_VoreCheck(caster, target, "SwallowLethalCheck")
                end)
            end
        end
    end
end

---Triggers whenever there's a skill check.
---@param eventName string Name of event passed from the func that called the roll.
---@param roller CHARACTER Roller.
---@param rollSubject CHARACTER Character they rolled against.
---@param resultType integer Result of roll. 0 == fail, 1 == success.
---@param isActiveRoll integer? Whether or not the rolling GUI popped up. 0 == no, 1 == yes.
---@param criticality CRITICALITYTYPE? Whether or not it was a crit and what kind. 0 == no crit, 1 == crit success, 2 == crit fail.
function SP_RollResults(eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
    if eventName == "SwallowLethalCheck" and resultType ~= 0 then
        _P('Lethal Swallow Success')
        Osi.ApplyStatus(rollSubject, "SP_Swallowed_Lethal", -1, 1, roller)
        Osi.ApplyStatus(roller, "SP_Stuffed", 1*6, 1, roller)
        SP_FillPredPreyTable(roller, rollSubject, 'SP_Target_Vore_Lethal')
    end
    if eventName == "StruggleCheck" and resultType ~= 0 then
        _P('Struggle Success')
        Osi.RemoveStatus(roller, "SP_Swallowed_Lethal")
        SP_SpellCast(rollSubject, "SP_Regurgitate_All")
    end
end

---Runs on session load.
function SP_OnSessionLoaded()
    -- Persistent variables are only available after SessionLoaded is triggered!
    _D(PersistentVars)
    _D(PredPreyTable)
    if PersistentVars['PredPreyTable'] ~= nil then
        _P('updated it')
        PredPreyTable = SP_Deepcopy(PersistentVars['PredPreyTable'])
    else
        PersistentVars['PredPreyTable'] = {}
    end
    if PersistentVars['WeightPlaceholderByCategory'] == nil then -- UNUSED
        _P('init WeightPlaceholderByCategory')
        PersistentVars['WeightPlaceholderByCategory'] = false
    end
    -- Nothing to config yet lmao
    -- Ext.RegisterConsoleCommand('VoreConfig', SP_VoreConfig);
    -- Ext.RegisterConsoleCommand('VoreConfigOptions', SP_VoreConfigOptions);
end

--Runs when reset command is sent to console.
function SP_On_reset_completed()
    for _, statPath in ipairs(StatPaths) do
        _P(statPath)
        Ext.Stats.LoadStatsFile(statPath, 1)
    end
    _P('Reloading stats!')
end

---Runs each turn in combat.
---@param character CHARACTER
function SP_OnTurn(character)
    _P("Turn Changed")
    for k, _ in pairs(PredPreyTable) do
        SP_TelePreyToPred(k)
    end
end

---Runs whenever you change game regions.
---@param levelName string? Name of new game region.
---@param isEditorMode integer?
function SP_OnLevelChange(levelName, isEditorMode)
    if PredPreyTable ~= nil then
        for k, v in pairs(PredPreyTable) do
            SP_SpellCast(k, 'SP_Regurgitate_All')
        end
    end
end

---Runs each time a status is applied.
---@param object CHARACTER Recipient of status.
---@param status string Internal name of status.
---@param cause GUIDSTRING? Thing that caused status to be applied.
---@param storyActionID integer?
function SP_OnStatusApplied(object, status, cause, storyActionID)
    if status == 'SP_Digesting_Tick' then
        _P("Applied " .. status .. " Status to" .. object)
        for _, v in ipairs(PredPreyTable[object]) do
            if Osi.HasActiveStatus(v, 'SP_Swallowed_Lethal') then
                _P(object)
                _P(v)
                SP_VoreCheck(object, v, "StruggleCheck")
            end
        end
    elseif status == 'SP_Item_Bound' then
        _P("Applied " .. status .. " Status to" .. object)
    elseif status == "DOWNED" and Osi.HasActiveStatus(object, 'SP_Swallowed_Lethal') ~= 0 then
        _P(object .. " Digested")
        local pred = SP_GetPredFromPrey(object)
        _P("pred name: " .. SP_GetDisplayNameFromGUID(pred))
        _P("prey name: " .. SP_GetDisplayNameFromGUID(object))
        Osi.TransferItemsToCharacter(object, pred)
        _P("Inventory Transferred to " .. pred)
    end
end

---Runs when someone dies.
---@param character CHARACTER
function SP_OnDeath(character)
    _P(character .. ' died.')
    if Osi.HasActiveStatus(character, 'SP_Swallowed_Lethal') and character ~= nil then
        local pred = SP_GetPredFromPrey(character)
        SP_SpellCast(pred, character)
    end

end

-- If you know where to get type hints for this, please let me know.
if Ext.Osiris == nil then Ext.Osiris = {} end

Ext.Osiris.RegisterListener("UsingSpellOnTarget", 6, "after", SP_OnSpellCastTarget)
Ext.Osiris.RegisterListener("CastedSpell", 5, "after", SP_SpellCast)
Ext.Osiris.RegisterListener("TurnStarted", 1, "after", SP_OnTurn)
Ext.Osiris.RegisterListener("RollResult", 6, "after", SP_RollResults)
Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "before", SP_OnLevelChange)
Ext.Osiris.RegisterListener("StatusApplied", 4, "after", SP_OnStatusApplied)
Ext.Osiris.RegisterListener("Died", 1, "after", SP_OnDeath)
Ext.Events.SessionLoaded:Subscribe(SP_OnSessionLoaded)
Ext.Events.ResetCompleted:Subscribe(SP_On_reset_completed)
