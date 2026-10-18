// Bridges Unreal types to the engine-independent gameplay core in Core/.
#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "CLTypes.h"
#include "CLAttributes.h"
#include "CLDribble.h"
#include "CLFinishing.h"
#include "CLJumpshot.h"
#include "CLShooting.h"
#include "CLCoreBridge.generated.h"

/** Unreal units per foot. The core works in feet like the web prototype. */
static constexpr double CLUnitsPerFoot = 30.48;

namespace CLBridge
{
	courtlife::Body ToCore(const FCLBody& Body);
	courtlife::Attributes ToCore(const TArray<int32>& Attributes);
	courtlife::JumpshotSettings ToCore(const FCLJumpshot& Jumpshot);
	courtlife::DribbleCombo ToCore(const FCLDribbleCombo& Combo);
	courtlife::Position ToCore(ECLPosition Position);
	int32 Rating(const FMyPlayerBuild& Build, courtlife::Attr Attr);
	FCLShotProfile FromCore(const courtlife::ShotProfile& Profile);
	ECLReleaseGrade FromCore(courtlife::ReleaseGrade Grade);
	ECLShotType FromCore(courtlife::FinishType Type);
	courtlife::FinishType ToCore(ECLShotType Type);
	inline ECLHand FromCore(courtlife::Hand Hand) { return Hand == courtlife::Hand::Right ? ECLHand::Right : ECLHand::Left; }
	inline courtlife::Hand ToCore(ECLHand Hand) { return Hand == ECLHand::Right ? courtlife::Hand::Right : courtlife::Hand::Left; }

	/**
	 * Core local offsets use (x, z) with the player facing +z and their right
	 * at -x. Unreal actors face +X with right at +Y.
	 */
	inline FVector LocalOffsetToWorld(const FRotator& Facing, double XFt, double ZFt)
	{
		const FRotationMatrix M(FRotator(0.0, Facing.Yaw, 0.0));
		return (M.GetUnitAxis(EAxis::X) * ZFt + M.GetUnitAxis(EAxis::Y) * -XFt) * CLUnitsPerFoot;
	}
}

UCLASS()
class COURTLIFE_API UCLBuildLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** Clamp everything to legal values (body limits, attribute caps & budget, combos). */
	UFUNCTION(BlueprintPure, Category = "CourtLife|Build")
	static FMyPlayerBuild NormalizeBuild(const FMyPlayerBuild& Build);

	UFUNCTION(BlueprintPure, Category = "CourtLife|Build")
	static FMyPlayerBuild MakeDefaultBuild();

	UFUNCTION(BlueprintPure, Category = "CourtLife|Build")
	static int32 OverallRating(const FMyPlayerBuild& Build);

	UFUNCTION(BlueprintPure, Category = "CourtLife|Build")
	static TArray<int32> AttributeCaps(const FCLBody& Body);

	/** Value actually allowed when the player drags one attribute slider. */
	UFUNCTION(BlueprintPure, Category = "CourtLife|Build")
	static int32 SetAttribute(const FMyPlayerBuild& Build, int32 AttributeIndex, int32 Value);

	UFUNCTION(BlueprintPure, Category = "CourtLife|Jumpshot")
	static FCLShotProfile ComputeShotProfile(const FMyPlayerBuild& Build);

	/** Layup or dunk for a shot from DistanceFt (to the rim) at SpeedFtPerSec; Jumper when too far. */
	UFUNCTION(BlueprintPure, Category = "CourtLife|Finishing")
	static ECLShotType ChooseFinish(const FMyPlayerBuild& Build, float DistanceFt, float SpeedFtPerSec);

	UFUNCTION(BlueprintPure, Category = "CourtLife|Dribble")
	static TArray<FString> ValidateCombo(const FMyPlayerBuild& Build, const FCLDribbleCombo& Combo);

	/** Import a "CL1." build code made in the CourtLife web creator. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Build")
	static bool ImportBuildCode(const FString& Code, FMyPlayerBuild& OutBuild, FString& OutError);
};
