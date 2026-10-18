// Data assets that connect build choices to authored content. Artists fill
// these in the editor; code never hard-references meshes or animations.
#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "CLAssets.generated.h"

class UAnimMontage;
class UAnimSequence;
class USkeletalMesh;
class UTexture2D;
class UMaterialInterface;
class UFont;

USTRUCT(BlueprintType)
struct FCLHandedMontage
{
	GENERATED_BODY()
	/** Move performed starting with the ball in the right hand. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) TObjectPtr<UAnimMontage> Right;
	/** Mirror for the left hand; leave empty to mirror Right at runtime via a mirror data table. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) TObjectPtr<UAnimMontage> Left;
};

/**
 * Animation content for gameplay. Jumpshots layer a lower-body base with two
 * upper-body releases blended by FCLShotProfile::ReleaseBlend; each base
 * montage carries a "Release" anim notify at FCLShotProfile's releaseT.
 */
UCLASS(BlueprintType)
class COURTLIFE_API UCLAnimSet : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Jumpshot") TMap<FName, TObjectPtr<UAnimMontage>> ShotBases;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Jumpshot") TMap<FName, TObjectPtr<UAnimSequence>> ShotReleases;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Dribble") TMap<FName, FCLHandedMontage> DribbleMoves;
	/** Finish montages keyed "layup" and "dunk"; each carries a "Release" notify at the core's release time. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Finishing") TMap<FName, TObjectPtr<UAnimMontage>> Finishes;

	virtual FPrimaryAssetId GetPrimaryAssetId() const override { return FPrimaryAssetId(TEXT("CLAnimSet"), GetFName()); }
};

USTRUCT(BlueprintType)
struct FCLCosmeticItem
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadOnly) FText DisplayName;
	/** Modular mesh sharing the body skeleton (leader-pose follower). */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) TSoftObjectPtr<USkeletalMesh> Mesh;
	/** Material with Primary/Secondary/Tertiary color params; optional. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) TSoftObjectPtr<UMaterialInterface> Material;
};

USTRUCT(BlueprintType)
struct FCLTattooDesign
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadOnly) FText DisplayName;
	/** Grayscale stencil: R = ink, G = accent. Empty for text designs. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) TSoftObjectPtr<UTexture2D> Stencil;
	UPROPERTY(EditAnywhere, BlueprintReadOnly) bool bDrawsText = false;
	/** Wraps the full limb (bands, sleeves) instead of a single placement. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) bool bWrapsLimb = false;
};

/** UV rectangle of a tattoo slot inside the body's tattoo atlas texture. */
USTRUCT(BlueprintType)
struct FCLTattooRegion
{
	GENERATED_BODY()
	UPROPERTY(EditAnywhere, BlueprintReadOnly) FBox2D UV = FBox2D(FVector2D(0, 0), FVector2D(1, 1));
	/** Limb circumference / length, so designs keep their proportions. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly) float Aspect = 1.f;
};

UCLASS(BlueprintType)
class COURTLIFE_API UCLCosmeticsCatalog : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hair") TMap<FName, FCLCosmeticItem> HairStyles;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hair") TMap<FName, FCLCosmeticItem> FacialHair;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Clothing") TMap<FName, FCLCosmeticItem> Jerseys;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Clothing") TMap<FName, FCLCosmeticItem> Shorts;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Clothing") TMap<FName, FCLCosmeticItem> Shoes;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Clothing") TMap<FName, FCLCosmeticItem> Socks;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Clothing") TMap<FName, FCLCosmeticItem> Accessories;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tattoos") TMap<FName, FCLTattooDesign> TattooDesigns;
	/** One entry per ECLTattooSlot, in enum order. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tattoos") TArray<FCLTattooRegion> TattooRegions;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tattoos") TObjectPtr<UFont> ScriptFont;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tattoos") int32 TattooAtlasSize = 2048;

	virtual FPrimaryAssetId GetPrimaryAssetId() const override { return FPrimaryAssetId(TEXT("CLCosmeticsCatalog"), GetFName()); }
};
