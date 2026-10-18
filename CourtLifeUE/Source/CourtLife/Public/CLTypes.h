// MyPlayer build data. Field-for-field compatible with the web creator's
// player JSON (courtlife/src/core/player.js) so build codes import directly.
#pragma once

#include "CoreMinimal.h"
#include "CLTypes.generated.h"

UENUM(BlueprintType)
enum class ECLPosition : uint8 { PG, SG, SF, PF, C };

UENUM(BlueprintType)
enum class ECLHand : uint8 { Right, Left };

UENUM(BlueprintType)
enum class ECLTattooSlot : uint8
{
	Neck, LeftUpperArm, RightUpperArm, LeftForearm, RightForearm, LeftHand, RightHand, LeftCalf, RightCalf
};

UENUM(BlueprintType)
enum class ECLReleaseGrade : uint8 { Green, SlightlyEarly, SlightlyLate, Early, Late };

USTRUCT(BlueprintType)
struct FCLBody
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 69, ClampMax = 87)) int32 HeightIn = 75;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 160, ClampMax = 290)) int32 WeightLb = 190;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) int32 WingspanIn = 79;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0, ClampMax = 1)) float Build = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor SkinTone = FLinearColor(0.27f, 0.09f, 0.02f);
};

USTRUCT(BlueprintType)
struct FCLFace
{
	GENERATED_BODY()
	/** Optional MetaHuman (or other) head preset; HairStyle etc. layer on top. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName HeadPreset;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName HairStyle = TEXT("fade");
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor HairColor = FLinearColor(0.01f, 0.01f, 0.01f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName FacialHair = TEXT("none");
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor FacialHairColor = FLinearColor(0.01f, 0.01f, 0.01f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor EyeColor = FLinearColor(0.05f, 0.02f, 0.01f);
};

/** One clothing piece: which mesh from the catalog and its colorway. */
USTRUCT(BlueprintType)
struct FCLGarment
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName Item;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor Primary = FLinearColor::White;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor Secondary = FLinearColor::Black;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor Tertiary = FLinearColor::White;
};

inline FCLGarment MakeGarment(FName Item, const FLinearColor& Primary, const FLinearColor& Secondary = FLinearColor::Black, const FLinearColor& Tertiary = FLinearColor::White)
{
	FCLGarment G;
	G.Item = Item;
	G.Primary = Primary;
	G.Secondary = Secondary;
	G.Tertiary = Tertiary;
	return G;
}

USTRUCT(BlueprintType)
struct FCLOutfit
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLGarment Jersey;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLGarment Shorts;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLGarment Shoes;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLGarment Socks;
	/** Headband, sleeves, wristbands... keyed by catalog item; absent = not worn. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite) TArray<FCLGarment> Accessories;
};

USTRUCT(BlueprintType)
struct FCLTattoo
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) ECLTattooSlot Slot = ECLTattooSlot::LeftForearm;
	/** Row in the cosmetics catalog's tattoo designs. "script"/"number" draw Text. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName Design = TEXT("tribal");
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor Ink = FLinearColor(0.006f, 0.006f, 0.006f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FLinearColor Accent = FLinearColor(0.26f, 0.f, 0.f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0.4, ClampMax = 1.6)) float Scale = 1.f;
	/** 0 = near the joint, 1 = far end of the limb. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0, ClampMax = 1)) float Offset = 0.5f;
	/** Wrap around the limb, 0 = front. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0, ClampMax = 1)) float Rotate = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FString Text;
};

USTRUCT(BlueprintType)
struct FCLJumpshot
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName Base = TEXT("classic");
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName Release1 = TEXT("highArc");
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName Release2 = TEXT("quickFlick");
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0, ClampMax = 100)) int32 Blend = 30;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 1, ClampMax = 5)) int32 Speed = 3;
};

USTRUCT(BlueprintType)
struct FCLComboStep
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FName Move = TEXT("crossover");
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0.6, ClampMax = 1.5)) float Speed = 1.f;
};

inline FCLComboStep MakeComboStep(FName Move, float Speed)
{
	FCLComboStep S;
	S.Move = Move;
	S.Speed = Speed;
	return S;
}

USTRUCT(BlueprintType)
struct FCLDribbleCombo
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FString Name = TEXT("Combo");
	/** Combo slot 0..7 (web keys 1,2,3,4,Q,E,R,F). Bound to an input action per slot. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0, ClampMax = 7)) int32 Slot = 0;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) TArray<FCLComboStep> Steps;
};

/** Number of attribute ratings; order matches courtlife::Attr. */
static constexpr int32 CLAttributeCount = 17;

USTRUCT(BlueprintType)
struct FMyPlayerBuild
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FGuid Id = FGuid::NewGuid();
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FString Name = TEXT("Rookie");
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ClampMin = 0, ClampMax = 99)) int32 Number = 0;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) ECLPosition Position = ECLPosition::PG;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLBody Body;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLFace Face;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLOutfit Outfit;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) TArray<FCLTattoo> Tattoos;
	/** CLAttributeCount ratings, 25..99, in courtlife::Attr order. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite) TArray<int32> Attributes;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) FCLJumpshot Jumpshot;
	UPROPERTY(EditAnywhere, BlueprintReadWrite) TArray<FCLDribbleCombo> Combos;
};

USTRUCT(BlueprintType)
struct FCLShotProfile
{
	GENERATED_BODY()
	UPROPERTY(BlueprintReadOnly) float DurationMs = 0.f;
	UPROPERTY(BlueprintReadOnly) float ReleaseTimeMs = 0.f;
	UPROPERTY(BlueprintReadOnly) float GreenWindowMs = 0.f;
	UPROPERTY(BlueprintReadOnly) float ReleaseHeightFt = 0.f;
	UPROPERTY(BlueprintReadOnly) float ContestResist = 0.f;
	UPROPERTY(BlueprintReadOnly) float Rhythm = 1.f;
	/** Montage play rate for the shot animation. */
	UPROPERTY(BlueprintReadOnly) float PlayRate = 1.f;
	/** Upper-body blend between Release1 (0) and Release2 (1) in the anim graph. */
	UPROPERTY(BlueprintReadOnly) float ReleaseBlend = 0.f;
};

USTRUCT(BlueprintType)
struct FCLShotResult
{
	GENERATED_BODY()
	UPROPERTY(BlueprintReadOnly) ECLReleaseGrade Grade = ECLReleaseGrade::Late;
	UPROPERTY(BlueprintReadOnly) float TimingDeltaMs = 0.f;
	UPROPERTY(BlueprintReadOnly) float Contest = 0.f;
	UPROPERTY(BlueprintReadOnly) float MakeChance = 0.f;
	UPROPERTY(BlueprintReadOnly) float DistanceFt = 0.f;
	UPROPERTY(BlueprintReadOnly) bool bThree = false;
	UPROPERTY(BlueprintReadOnly) bool bMade = false;
};
