# B006 — Dropdown Staat Niet Direct Onder Input

Status: 🟢 approved
Priority: High
Added: 2026-03-14

## Probleem
De dropdown van de searchableCombobox staat niet recht onder het input veld. Er zit een gap of offset waardoor de dropdown visueel los lijkt van de input.

## Root Cause
CSS positioning conflict: zowel `.slds-form-element__control` als `.slds-combobox` hebben `position: relative`. De dropdown (`position: absolute; top: 100%`) positioneert zich t.o.v. `.slds-combobox`, maar die bevat niet alleen het input element.

## Fix
- Verwijder `position: relative` van `.slds-form-element__control` (is overbodig als `.slds-combobox` al relative is)
- Zorg dat `.slds-dropdown` zich positioneert direct onder het input element
- Optioneel: `margin-top: 1px` of `margin-top: 0` op dropdown voor pixel-perfect alignment
- Test met alle 3 pickers (Metadata Type, Object, Component) in metadataPicker

## Geraakt
- searchableCombobox.css

## Complexiteit
S — puur CSS fix
