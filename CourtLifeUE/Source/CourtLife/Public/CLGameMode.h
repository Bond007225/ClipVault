#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "CLTypes.h"
#include "CLGameMode.generated.h"

class ACLBallerCharacter;

USTRUCT(BlueprintType)
struct FCLSessionStats
{
	GENERATED_BODY()
	UPROPERTY(BlueprintReadOnly) int32 Points = 0;
	UPROPERTY(BlueprintReadOnly) int32 FieldGoalsMade = 0;
	UPROPERTY(BlueprintReadOnly) int32 FieldGoalsAttempted = 0;
	UPROPERTY(BlueprintReadOnly) int32 ThreesMade = 0;
	UPROPERTY(BlueprintReadOnly) int32 ThreesAttempted = 0;
	UPROPERTY(BlueprintReadOnly) int32 Greens = 0;
	UPROPERTY(BlueprintReadOnly) int32 AnklesBroken = 0;
};

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FCLOnStatsChanged, const FCLSessionStats&, Stats);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FCLOnShotFeedback, const FCLShotResult&, Result);

/** 1-on-1 half court: spawns the defender, wires gameplay events, keeps stats for the HUD. */
UCLASS()
class COURTLIFE_API ACLGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	virtual void StartPlay() override;

	UFUNCTION(BlueprintCallable, Category = "CourtLife") void SetDefenderEnabled(bool bEnabled);

	UPROPERTY(BlueprintAssignable) FCLOnStatsChanged OnStatsChanged;
	UPROPERTY(BlueprintAssignable) FCLOnShotFeedback OnShotFeedback;
	UPROPERTY(BlueprintReadOnly, Category = "CourtLife") FCLSessionStats Stats;

protected:
	UPROPERTY(EditDefaultsOnly, Category = "CourtLife") TSubclassOf<APawn> DefenderClass;
	/** Where the defender starts, in court feet (x, z). */
	UPROPERTY(EditDefaultsOnly, Category = "CourtLife") FVector2D DefenderStart = FVector2D(0.0, 20.0);

private:
	UFUNCTION() void HandleShot(const FCLShotResult& Result);
	UFUNCTION() void HandleBasket(int32 Points);
	UFUNCTION() void HandleCombo(const FString& ComboName, float Effectiveness);

	UPROPERTY() TObjectPtr<ACLBallerCharacter> Player;
	UPROPERTY() TObjectPtr<APawn> Defender;
};
