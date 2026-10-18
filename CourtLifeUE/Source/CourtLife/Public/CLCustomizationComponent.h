#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "CLTypes.h"
#include "CLCustomizationComponent.generated.h"

class UCLCosmeticsCatalog;
class USkeletalMeshComponent;
class UTextureRenderTarget2D;
class UMaterialInstanceDynamic;
struct FCLCosmeticItem;

/**
 * Dresses the owning character from a build: body proportions, skin,
 * modular clothing (leader-pose followers of the body mesh), hair, colorways
 * and a tattoo atlas painted at runtime and fed to the skin material.
 *
 * Material contract (set up by tech art):
 *  - Body skin material: vector "SkinTone", texture "TattooAtlas" (RGBA, A = coverage).
 *  - Garment materials: vectors "Primary", "Secondary", "Tertiary"; jersey also
 *    has scalar "Number" and texture "NameplateText" if desired.
 *  - Sleeves/garments covering skin simply render on top, hiding tattoos.
 */
UCLASS(ClassGroup = (CourtLife), meta = (BlueprintSpawnableComponent))
class COURTLIFE_API UCLCustomizationComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Customization")
	void ApplyBuild(const FMyPlayerBuild& Build, UCLCosmeticsCatalog* Catalog);

	/** Re-paint only the tattoo atlas (cheap; call while editing tattoos). */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Customization")
	void RepaintTattoos(const TArray<FCLTattoo>& Tattoos, int32 JerseyNumber);

	/** Reference body height the base skeleton was authored at. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Customization") float ReferenceHeightIn = 78.f;
	/** Morph targets on the body mesh driven by weight and muscle (optional). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Customization") FName HeavyMorph = TEXT("body_heavy");
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Customization") FName MuscleMorph = TEXT("body_muscular");

private:
	USkeletalMeshComponent* GetBody() const;
	USkeletalMeshComponent* Equip(FName SlotName, const FCLCosmeticItem* Item, const FCLGarment* Colors);
	void ClearEquipped();

	UPROPERTY() TObjectPtr<UCLCosmeticsCatalog> ActiveCatalog;
	UPROPERTY() TMap<FName, TObjectPtr<USkeletalMeshComponent>> Equipped;
	UPROPERTY() TObjectPtr<UTextureRenderTarget2D> TattooAtlas;
	UPROPERTY() TArray<TObjectPtr<UMaterialInstanceDynamic>> SkinMaterials;
};
