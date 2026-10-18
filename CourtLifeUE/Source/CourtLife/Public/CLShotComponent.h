#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "CLTypes.h"
#include "CLFinishing.h"
#include "CLShotComponent.generated.h"

class UCLAnimSet;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FCLOnShotReleased, const FCLShotResult&, Result);

/**
 * Owns the shot meter. Press starts the player's custom jumpshot montage;
 * release (or the auto-release at the end of the motion) grades timing
 * against the build's green window and rolls the make. Pressing close to the
 * rim picks a layup or dunk instead (courtlife::ChooseFinish), which has no
 * meter yet and resolves itself at the finish profile's release time.
 */
UCLASS(ClassGroup = (CourtLife), meta = (BlueprintSpawnableComponent))
class COURTLIFE_API UCLShotComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UCLShotComponent();
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	void Configure(const FMyPlayerBuild& InBuild, UCLAnimSet* InAnimSet);

	UFUNCTION(BlueprintCallable, Category = "CourtLife|Shot") bool BeginShot();
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Shot") void ReleaseShot();

	UFUNCTION(BlueprintPure, Category = "CourtLife|Shot") bool IsShooting() const { return bShooting; }
	/** What the current (or last) attempt is; hide the meter unless Jumper. */
	UFUNCTION(BlueprintPure, Category = "CourtLife|Shot") ECLShotType GetShotType() const { return ShotType; }
	/** 0..1 meter fill; the green band is GetGreenBand(). */
	UFUNCTION(BlueprintPure, Category = "CourtLife|Shot") float GetMeterFill() const;
	UFUNCTION(BlueprintPure, Category = "CourtLife|Shot") FVector2D GetGreenBand() const;
	UFUNCTION(BlueprintPure, Category = "CourtLife|Shot") const FCLShotProfile& GetProfile() const { return Profile; }

	/** Set by the game mode: who is guarding us right now (may be null). */
	UPROPERTY(BlueprintReadWrite, Category = "CourtLife|Shot") TWeakObjectPtr<AActor> Defender;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Shot") int32 DefenderHeightIn = 79;

	UPROPERTY(BlueprintAssignable) FCLOnShotReleased OnShotReleased;

private:
	FMyPlayerBuild Build;
	FCLShotProfile Profile;
	UPROPERTY() TObjectPtr<UCLAnimSet> AnimSet;
	bool bShooting = false;
	bool bReleased = false;
	float HeldMs = 0.f;

	void ResolveFinish();
	ECLShotType ShotType = ECLShotType::Jumper;
	courtlife::FinishProfile Finish;
	int32 FinishRating = 0;
	double FinishDistanceFt = 0.0;
};
