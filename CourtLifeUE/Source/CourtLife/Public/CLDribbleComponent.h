#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "CLTypes.h"
#include "CLDribble.h"
#include "CLDribbleComponent.generated.h"

class UCLAnimSet;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FCLOnComboFinished, const FString&, ComboName, float, Effectiveness);

/**
 * Runs the player's custom dribble combos. Each step plays that move's
 * montage (per hand) at the step's speed; the core timeline decides hand
 * switches and how far the handler travels. With root-motion montages set
 * bUseRootMotion so the animation moves the player instead of code.
 */
UCLASS(ClassGroup = (CourtLife), meta = (BlueprintSpawnableComponent))
class COURTLIFE_API UCLDribbleComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UCLDribbleComponent();
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	void Configure(const FMyPlayerBuild& InBuild, UCLAnimSet* InAnimSet);

	/** Fire the combo bound to a slot (0..7). Returns false if busy or empty. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Dribble") bool StartCombo(int32 Slot);
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Dribble") void Cancel();

	UFUNCTION(BlueprintPure, Category = "CourtLife|Dribble") bool IsInCombo() const { return bActive; }
	UFUNCTION(BlueprintPure, Category = "CourtLife|Dribble") ECLHand GetBallHand() const { return BallHand; }
	/** For the anim graph: lean/rise of the current move. */
	UFUNCTION(BlueprintPure, Category = "CourtLife|Dribble") float GetLean() const { return Lean; }
	UFUNCTION(BlueprintPure, Category = "CourtLife|Dribble") float GetRise() const { return Rise; }

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Dribble") bool bUseRootMotion = false;

	UPROPERTY(BlueprintAssignable) FCLOnComboFinished OnComboFinished;

private:
	void PlaySegmentMontage(int32 SegmentIndex);

	FMyPlayerBuild Build;
	UPROPERTY() TObjectPtr<UCLAnimSet> AnimSet;
	courtlife::ComboTimeline Timeline;
	FString ActiveName;
	bool bActive = false;
	float ElapsedMs = 0.f;
	int32 PlayingSegment = INDEX_NONE;
	FVector StartLocation = FVector::ZeroVector;
	FRotator StartFacing = FRotator::ZeroRotator;
	ECLHand BallHand = ECLHand::Right;
	float Lean = 0.f;
	float Rise = 0.f;
};
