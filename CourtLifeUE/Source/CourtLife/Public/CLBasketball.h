#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "CLBasketball.generated.h"

class UStaticMeshComponent;
class ACLCourt;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FCLOnBasket, int32, Points);
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FCLOnBallLoose);

UENUM(BlueprintType)
enum class ECLBallState : uint8 { Held, Flight, ThroughNet, Loose };

/**
 * The ball. Shot outcomes are decided by the shot component (timing,
 * contest, ratings); the ball then flies a scripted arc to the rim and hands
 * over to physics, so makes always drop and misses always clank.
 */
UCLASS()
class COURTLIFE_API ACLBasketball : public AActor
{
	GENERATED_BODY()

public:
	ACLBasketball();
	virtual void Tick(float DeltaSeconds) override;

	UFUNCTION(BlueprintCallable, Category = "CourtLife|Ball")
	void Hold(USceneComponent* Hand, FName Socket);

	/** Launch from the current position toward the court's rim. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Ball")
	void Shoot(bool bMake, int32 Points, float DistanceFt, float FlightTimeSec = 0.f);

	/** Knock the ball loose from the hand (a blocked finish). Velocity in uu/s. */
	UFUNCTION(BlueprintCallable, Category = "CourtLife|Ball")
	void Deflect(const FVector& InVelocity);

	UFUNCTION(BlueprintPure, Category = "CourtLife|Ball")
	ECLBallState GetState() const { return State; }

	UPROPERTY(BlueprintAssignable) FCLOnBasket OnBasket;
	UPROPERTY(BlueprintAssignable) FCLOnBallLoose OnLoose;

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly) TObjectPtr<UStaticMeshComponent> Mesh;

private:
	void BecomeLoose(const FVector& Velocity);

	ECLBallState State = ECLBallState::Held;
	FVector Velocity = FVector::ZeroVector;
	float FlightElapsed = 0.f;
	float FlightTime = 0.f;
	bool bWillMake = false;
	int32 PendingPoints = 2;
	TWeakObjectPtr<ACLCourt> Court;
};
