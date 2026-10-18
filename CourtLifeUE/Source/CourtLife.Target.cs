using UnrealBuildTool;

public class CourtLifeTarget : TargetRules
{
	public CourtLifeTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("CourtLife");
	}
}
