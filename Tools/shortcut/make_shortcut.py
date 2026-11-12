#!/usr/bin/env python3
"""Writes the unsigned "Move Podcasts to Jimmy" shortcut.

Get Podcasts from Library -> Get Details of Podcast (Store ID) -> Combine Text (new lines)
-> URL Encode -> Open jimmy://import?text=<links>. Jimmy reads the links (see
Onboarding.importText(from:)) and imports them. Sign the output with
`shortcuts sign --mode anyone` (Tools/shortcut/build.sh) before shipping it.
"""
import plistlib
import sys
import uuid


def ref(output_uuid, name):
    return {"Value": {"OutputUUID": output_uuid, "Type": "ActionOutput", "OutputName": name},
            "WFSerializationType": "WFTextTokenAttachment"}


def action(identifier, uid, **parameters):
    return {"WFWorkflowActionIdentifier": identifier,
            "WFWorkflowActionParameters": {"UUID": uid, **parameters}}


podcasts, details, combined, encoded = (str(uuid.uuid4()).upper() for _ in range(4))
placeholder = "￼"
prefix = "jimmy://import?text="

shortcut = {
    "WFWorkflowClientVersion": "2607.0.2",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 61440},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowTypes": [],
    "WFWorkflowHasShortcutInputVariables": False,
    "WFWorkflowActions": [
        action("is.workflow.actions.getpodcastsfromlibrary", podcasts),
        action("is.workflow.actions.properties.podcastshow", details,
               WFInput=ref(podcasts, "Podcasts"), WFContentItemPropertyName="Store ID"),
        action("is.workflow.actions.text.combine", combined,
               text=ref(details, "Store ID"), WFTextSeparator="New Lines"),
        action("is.workflow.actions.urlencode", encoded,
               WFInput=ref(combined, "Combined Text"), WFEncodeMode="Encode"),
        action("is.workflow.actions.openurl", str(uuid.uuid4()).upper(),
               WFInput={"Value": {"string": prefix + placeholder,
                                  "attachmentsByRange": {f"{{{len(prefix)}, 1}}": {
                                      "OutputUUID": encoded, "Type": "ActionOutput",
                                      "OutputName": "URL Encoded Text"}}},
                        "WFSerializationType": "WFTextTokenString"}),
    ],
}

with open(sys.argv[1], "wb") as out:
    plistlib.dump(shortcut, out, fmt=plistlib.FMT_BINARY)
