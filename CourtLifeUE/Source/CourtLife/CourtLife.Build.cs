using System.IO;
using UnrealBuildTool;

public class CourtLife : ModuleRules
{
	public CourtLife(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput", "UMG", "AIModule"
		});
		PrivateDependencyModuleNames.AddRange(new string[] { "Json", "JsonUtilities", "SlateCore" });

		// Engine-independent gameplay core (also built by Tests/CMakeLists.txt).
		PublicIncludePaths.Add(Path.Combine(ModuleDirectory, "Core"));
	}
}
