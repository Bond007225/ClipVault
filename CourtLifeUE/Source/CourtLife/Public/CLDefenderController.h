#pragma once

#include "CoreMinimal.h"
#include "AIController.h"
#include "CLDefender.h"
#include "CLDefenderController.generated.h"

class UAnimMontage;

/** On-ball defender driven by the shared core brain (courtlife::StepDefender). */
UCLASS()
class COURTLIFE_API ACLDefenderController : public AAIController
{
	GENERATED_BODY()

public:
	ACLDefenderController();
	virtual void Tick(float DeltaSeconds) override;
	virtual void OnPossess(APawn* InPawn) override;

	UFUNCTION(BlueprintCallable, Category = "CourtLife|Defense") void SetHandler(AActor* InHandler) { Handler = InHandler; }
	/** Called when the handler finishes a combo; may break our ankles. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Defense") void ReactToCombo(float Effectiveness, int32 BallHandle);
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Defense") void ReactToShot();

	UFUNCTION(BlueprintPure, Category = "CourtLife|Defense") bool IsStumbling() const { return State.stumble > 0; }

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Defense") int32 PerimeterDefense = 82;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Defense") int32 Speed = 78;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CourtLife|Defense") int32 Acceleration = 78;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Defense") TObjectPtr<UAnimMontage> StumbleMontage;
	UPROPERTY(EditAnywhere, Category = "CourtLife|Defense") TObjectPtr<UAnimMontage> ContestMontage;

private:
	void PlayMontage(UAnimMontage* Montage);

	courtlife::DefenderState State;
	TWeakObjectPtr<AActor> Handler;
};
